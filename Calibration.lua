local addonName, GCP = ...

GCP.Calibration = {}
local Calibration = GCP.Calibration

-- ---------------------------------------------------------------------------
-- SELF CALIBRATION (0.9.0)
--
-- Die Gewichte der Opportunity-Bewertung stehen in Constants.lua. Sie sind
-- begruendet, aber sie sind nicht gemessen - sie stammen aus Ueberlegung, nicht
-- aus Ergebnissen. Sobald genuegend ECHTE Ergebnisse vorliegen, kann Gold
-- Copilot sie an den eigenen Realm und den eigenen Spielstil anpassen.
--
-- DAS IST KEINE KI. Es gibt kein Modell, keine Blackbox und keinen Zufall.
-- Es gibt eine einzige, nachvollziehbare Rechnung:
--
--     angepasst = standard + (gemessen - standard) * gewicht
--     gewicht   = n / (n + PRIOR)          -- Regression zum Standard
--
-- Das ist Bayes'sches Schrumpfen in seiner einfachsten Form. Es hat genau die
-- Eigenschaft, die hier gebraucht wird: Bei wenigen Daten bleibt fast alles
-- beim Standard, bei vielen Daten naehert es sich der Messung an - und es
-- springt nie.
--
-- SICHERHEITSREGELN, jede einzeln begruendet:
--   * MIN_SAMPLES je Kategorie. Aus fuenf Geschaeften laesst sich nicht
--     lernen, dass "Resale nicht funktioniert".
--   * PRIOR-Gewicht. Selbst bei 100 Faellen bleibt ein Rest Standard stehen.
--   * Harte Min-/Max-Grenzen je Faktor. Ein Faktor kann sich hoechstens
--     halbieren oder verdoppeln, egal was die Daten sagen.
--   * MAX_STEP je Neuberechnung. Ein Faktor bewegt sich nie um mehr als einen
--     kleinen Schritt auf einmal.
--   * Das Standardmodell bleibt gespeichert und ist jederzeit wiederherstellbar.
--   * Die Kalibrierung ist versioniert. Aendert sich das Modell, faengt sie neu
--     an, statt auf alten Zahlen weiterzurechnen.
--
-- Angepasst werden AUSSCHLIESSLICH Multiplikatoren auf den fertigen Score je
-- Chancenart - nicht die Formel selbst und nicht die einzelnen Summanden. Der
-- Rechenweg bleibt derselbe und bleibt nachvollziehbar; kalibriert wird nur,
-- wie stark eine Chancenart im Vergleich zu den anderen zaehlt.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.CALIBRATION
end

Calibration.revision = 0

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function now()
    if type(time) == "function" then
        local ok, value = pcall(time)
        if ok and type(value) == "number" then return value end
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- Speicher
--
--   db.calibration = {
--       version = 1,
--       model = 1,                       -- Modellversion; Wechsel = Neustart
--       factors = { craft = 1.06, resale = 0.94 },
--       samples = { craft = 47, resale = 31 },
--       updatedAt = ..., enabled = true,
--   }
-- ---------------------------------------------------------------------------

function Calibration:EnsureStore()
    local db = GCP.db
    if not db then return nil end
    local C = config()
    local profile = GCP:Profile()
    local store = profile.calibration
    if type(store) ~= "table" or store.version ~= C.STORE_VERSION
        or store.model ~= C.MODEL_VERSION then
        store = {
            version = C.STORE_VERSION,
            model = C.MODEL_VERSION,
            factors = {},
            samples = {},
            enabled = C.DEFAULT_ENABLED,
        }
        profile.calibration = store
    end
    if type(store.factors) ~= "table" then store.factors = {} end
    if type(store.samples) ~= "table" then store.samples = {} end
    if store.enabled == nil then store.enabled = C.DEFAULT_ENABLED end
    return store
end

function Calibration:IsEnabled()
    local store = self:EnsureStore()
    return store and store.enabled and true or false
end

function Calibration:SetEnabled(enabled)
    local store = self:EnsureStore()
    if not store then return false end
    store.enabled = enabled and true or false
    self.revision = self.revision + 1
    if GCP.Opportunity then GCP.Opportunity:Invalidate() end
    return true
end

function Calibration:Reset()
    local db = GCP.db
    if not db then return false end
    GCP:Profile().calibration = nil
    self:EnsureStore()
    self.revision = self.revision + 1
    if GCP.Opportunity then GCP.Opportunity:Invalidate() end
    return true
end

-- ---------------------------------------------------------------------------
-- Rechnung
-- ---------------------------------------------------------------------------

-- Der gemessene Faktor einer Chancenart: Wie gut ist sie im Vergleich zum
-- Durchschnitt aller Arten ausgegangen? Bezugsgroesse ist ausdruecklich der
-- eigene Durchschnitt, nicht eine absolute Erwartung - "60 % Trefferquote"
-- ist ohne Vergleich keine Zahl.
function Calibration:MeasuredFactor(cell, baseline)
    if type(cell) ~= "table" or (tonumber(cell.n) or 0) == 0 then return nil end
    baseline = tonumber(baseline)
    if not baseline or baseline <= 0 then return nil end
    local hitRate = cell.hitRate or 0
    -- Eine Trefferquote von 0 darf nicht zu Faktor 0 fuehren: Auch eine
    -- Chancenart, die dreimal danebenlag, ist nicht wertlos. Deshalb wird um
    -- die Grundlinie herum gemessen und danach hart begrenzt.
    return hitRate / baseline
end

function Calibration:Update(force)
    local store = self:EnsureStore()
    if not store then return false, "keine Datenbank" end
    if not store.enabled and not force then return false, "abgeschaltet" end
    local C = config()
    local report = GCP.Analytics:GetReport(true)
    if report.total.n < C.MIN_TOTAL_SAMPLES then
        return false, string.format("zu wenige abgeschlossene Fälle (%d von %d)",
            report.total.n, C.MIN_TOTAL_SAMPLES)
    end
    local baseline = report.total.hitRate
    if not baseline or baseline <= 0 then return false, "keine Grundlinie" end

    local changed = 0
    for kind, cell in pairs(report.byType) do
        if cell.n >= C.MIN_SAMPLES then
            local measured = self:MeasuredFactor(cell, baseline)
            if measured then
                local weight = cell.n / (cell.n + C.PRIOR)
                local target = 1 + (measured - 1) * weight
                target = clamp(target, C.MIN_FACTOR, C.MAX_FACTOR)
                local current = store.factors[kind] or 1
                -- Kleine Schritte: Ein Faktor bewegt sich nie sprunghaft, auch
                -- wenn die Messung das nahelegt.
                local step = clamp(target - current, -C.MAX_STEP, C.MAX_STEP)
                local updated = clamp(current + step, C.MIN_FACTOR, C.MAX_FACTOR)
                if math.abs(updated - current) > 1e-6 then changed = changed + 1 end
                store.factors[kind] = updated
                store.samples[kind] = cell.n
            end
        end
    end
    store.updatedAt = now()
    store.totalSamples = report.total.n
    self.revision = self.revision + 1
    if GCP.Opportunity then GCP.Opportunity:Invalidate() end
    return true, changed
end

-- Der Faktor, mit dem die Opportunity Engine rechnet. Ohne Kalibrierung ist er
-- exakt 1 - dann ist der Score Punkt fuer Punkt derselbe wie vorher.
function Calibration:FactorFor(kind)
    local store = self:EnsureStore()
    if not store or not store.enabled then return 1 end
    local factor = store.factors[kind]
    if type(factor) ~= "number" then return 1 end
    local C = config()
    return clamp(factor, C.MIN_FACTOR, C.MAX_FACTOR)
end

-- ---------------------------------------------------------------------------
-- Darstellung
-- ---------------------------------------------------------------------------

function Calibration:ModelLabel()
    local store = self:EnsureStore()
    if not store or not store.enabled then return "STANDARD" end
    local count = 0
    for _ in pairs(store.factors) do count = count + 1 end
    if count == 0 then return "STANDARD" end
    return string.format("PERSÖNLICH KALIBRIERT (%d Ergebnisse)",
        store.totalSamples or 0)
end

function Calibration:Lines()
    local store = self:EnsureStore()
    local C = config()
    local lines = {}
    lines[#lines + 1] = "Modell: " .. self:ModelLabel()
    if not store then return lines end
    if not store.enabled then
        lines[#lines + 1] = "Die Kalibrierung ist abgeschaltet – es gilt das "
            .. "Standardmodell aus Constants.lua."
        return lines
    end
    local report = GCP.Analytics:GetReport()
    if report.total.n < C.MIN_TOTAL_SAMPLES then
        lines[#lines + 1] = string.format(
            "Noch nicht genug Ergebnisse: %d von %d abgeschlossenen Fällen.",
            report.total.n, C.MIN_TOTAL_SAMPLES)
        lines[#lines + 1] = "Bis dahin gilt unverändert das Standardmodell."
        return lines
    end
    local any = false
    for kind, factor in pairs(store.factors) do
        any = true
        lines[#lines + 1] = string.format("%s: ×%.2f  (n=%d)",
            GCP.Opportunity:TypeLabel(kind) or kind, factor, store.samples[kind] or 0)
    end
    if not any then
        lines[#lines + 1] = "Noch keine Chancenart über der Mindeststichprobe."
    end
    lines[#lines + 1] = string.format("Grenzen: ×%.2f bis ×%.2f, "
        .. "höchstens %.2f Änderung je Durchlauf.", C.MIN_FACTOR, C.MAX_FACTOR, C.MAX_STEP)
    return lines
end
