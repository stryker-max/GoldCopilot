local addonName, GCP = ...

GCP.Analytics = {}
local Analytics = GCP.Analytics

-- ---------------------------------------------------------------------------
-- MODEL PERFORMANCE (0.9.0)
--
-- Seit 0.6 schreibt das Chancen-Protokoll mit, was die Engine wann behauptet
-- hat; seit 0.8 auch, was daraus geworden ist. Dieses Modul stellt zum ersten
-- Mal die unbequeme Frage:
--
--     "Hat das eigentlich gestimmt?"
--
-- Ausgewertet wird nach Chancenart, nach Score-Band, nach Market Score, nach
-- Future Signal, nach Hype und nach Liquiditaet. Immer mit der
-- Stichprobengroesse daneben, und immer mit einer klaren Markierung, wenn die
-- Stichprobe zu klein fuer eine Aussage ist.
--
--     Craft Opportunities   83 % positive Outcomes   n=47
--     Future Catalyst       67 %                     n=6   LOW SAMPLE
--
-- Das zweite ist keine Erkenntnis. Es sieht nur so aus wie eine, und genau
-- deshalb steht LOW SAMPLE daneben.
--
-- WAS HIER AUSDRUECKLICH NICHT PASSIERT:
--   * Keine Anpassung von Gewichten. Das macht Calibration.lua, und auch das
--     nur unter strengen Bedingungen.
--   * Keine Aussage aus OPEN- oder UNKNOWN-Eintraegen. Gezaehlt wird nur, was
--     abgeschlossen ist.
--   * Keine Signifikanztests, die es nicht hergibt. Eine Trefferquote aus
--     sechs Faellen ist eine Trefferquote aus sechs Faellen.
-- ---------------------------------------------------------------------------

local function config()
    return GCP.Constants.ANALYTICS
end

local function isNumber(value)
    return type(value) == "number"
end

Analytics.cache = nil
Analytics.cacheRevision = nil

-- Score-Baender, in die eine Vorhersage einsortiert wird. Bewusst grob: Vier
-- Baender ueber 100 Punkte ergeben Zellen, die sich fuellen; zwanzig Baender
-- ergeben zwanzig leere Zellen.
Analytics.BANDS = {
    { min = 85, label = "85–100" },
    { min = 70, label = "70–84" },
    { min = 55, label = "55–69" },
    { min = 0,  label = "unter 55" },
}

function Analytics:BandOf(score)
    if not isNumber(score) then return nil end
    for _, band in ipairs(self.BANDS) do
        if score >= band.min then return band.label end
    end
    return self.BANDS[#self.BANDS].label
end

local function newCell()
    return { n = 0, wins = 0, losses = 0, profit = 0, loss = 0,
        expected = 0, realized = 0, holdingHours = 0, holdingCount = 0 }
end

local function addOutcome(cell, entry)
    cell.n = cell.n + 1
    if entry.outcome == "WIN" then
        cell.wins = cell.wins + 1
        cell.profit = cell.profit + math.max(entry.realizedProfit or 0, 0)
    else
        cell.losses = cell.losses + 1
        cell.loss = cell.loss + math.abs(math.min(entry.realizedProfit or 0, 0))
    end
    cell.expected = cell.expected + (entry.expectedProfit or 0)
    cell.realized = cell.realized + (entry.realizedProfit or 0)
    if isNumber(entry.holdingHours) then
        cell.holdingHours = cell.holdingHours + entry.holdingHours
        cell.holdingCount = cell.holdingCount + 1
    end
end

local function finishCell(cell, minSamples)
    if cell.n == 0 then return cell end
    cell.hitRate = cell.wins / cell.n
    cell.netProfit = cell.profit - cell.loss
    cell.lowSample = cell.n < minSamples
    if cell.expected > 0 then
        cell.accuracy = cell.realized / cell.expected
    end
    if cell.holdingCount > 0 then
        cell.medianHoldingHours = cell.holdingHours / cell.holdingCount
    end
    return cell
end

-- ---------------------------------------------------------------------------
-- Auswertung
-- ---------------------------------------------------------------------------

function Analytics:Compute()
    local history = GCP.Opportunity and GCP.Opportunity:EnsureHistory()
    local C = config()
    local report = {
        byType = {}, byScoreBand = {}, byMarketBand = {}, byFutureBand = {},
        byHypeBand = {}, byLiquidityBand = {}, byConfidence = {},
        total = newCell(), open = 0, unknown = 0, entries = 0,
        minSamples = C.MIN_SAMPLES,
    }
    if not history then return report end

    local function cell(bucketName, key)
        if key == nil then return nil end
        local bucketTable = report[bucketName]
        local found = bucketTable[key]
        if not found then
            found = newCell()
            bucketTable[key] = found
        end
        return found
    end

    for _, entry in ipairs(history) do
        if type(entry) == "table" then
            report.entries = report.entries + 1
            if entry.outcome == "OPEN" then
                report.open = report.open + 1
            elseif entry.outcome == "WIN" or entry.outcome == "LOSS" then
                addOutcome(report.total, entry)
                local buckets = {
                    { "byType", entry.type },
                    { "byScoreBand", self:BandOf(entry.opportunityScore) },
                    { "byMarketBand", self:BandOf(entry.marketScore) },
                    { "byFutureBand", self:BandOf(entry.futureDemandScore) },
                    { "byHypeBand", self:BandOf(entry.hypeScore) },
                    { "byLiquidityBand", self:BandOf(entry.liquidityScore) },
                    { "byConfidence", entry.confidence },
                }
                for _, pair in ipairs(buckets) do
                    local target = cell(pair[1], pair[2])
                    if target then addOutcome(target, entry) end
                end
            elseif entry.outcome ~= nil then
                report.unknown = report.unknown + 1
            end
        end
    end

    finishCell(report.total, C.MIN_SAMPLES)
    for _, bucketName in ipairs({ "byType", "byScoreBand", "byMarketBand",
        "byFutureBand", "byHypeBand", "byLiquidityBand", "byConfidence" }) do
        for _, found in pairs(report[bucketName]) do
            finishCell(found, C.MIN_SAMPLES)
        end
    end
    return report
end

function Analytics:GetReport(force)
    local revision = (GCP.Ledger and GCP.Ledger.revision or 0)
        + (GCP.Opportunity and #(GCP.Opportunity:EnsureHistory() or {}) or 0)
    if not force and self.cache and self.cacheRevision == revision then
        return self.cache
    end
    local report = self:Compute()
    self.cache = report
    self.cacheRevision = revision
    return report
end

function Analytics:Invalidate()
    self.cache = nil
    self.cacheRevision = nil
end

-- ---------------------------------------------------------------------------
-- Darstellung
-- ---------------------------------------------------------------------------

function Analytics:FormatCell(label, cell)
    label = tostring(label or "?")
    if type(cell) ~= "table" or (tonumber(cell.n) or 0) == 0 then
        return string.format("%s: noch keine abgeschlossenen Fälle", label)
    end
    local text = string.format("%s: %.0f %% positiv · n=%.0f", label,
        (tonumber(cell.hitRate) or 0) * 100, tonumber(cell.n) or 0)
    if cell.lowSample then text = text .. "  LOW SAMPLE" end
    return text
end

function Analytics:Lines()
    local report = self:GetReport()
    local lines = {}
    if report.total.n == 0 then
        lines[#lines + 1] = "Noch keine abgeschlossenen Empfehlungen – die Auswertung "
            .. "entsteht, sobald aus Chancen echte Käufe und Verkäufe werden."
        if report.open > 0 then
            lines[#lines + 1] = string.format("%d Empfehlung(en) sind noch offen.",
                report.open)
        end
        return lines
    end
    lines[#lines + 1] = self:FormatCell("Alle Empfehlungen", report.total)
    if report.total.accuracy then
        lines[#lines + 1] = string.format(
            "Realisiert gegenüber theoretisch erwartet: %.0f %%",
            report.total.accuracy * 100)
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = "Nach Chancenart:"
    for kind, cell in pairs(report.byType) do
        lines[#lines + 1] = "  " .. self:FormatCell(
            GCP.Opportunity:TypeLabel(kind) or kind, cell)
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = "Nach Opportunity Score:"
    for _, band in ipairs(self.BANDS) do
        local cell = report.byScoreBand[band.label]
        if cell then lines[#lines + 1] = "  " .. self:FormatCell(band.label, cell) end
    end
    return lines
end

-- Die Zahl, die die Kalibrierung braucht: Wie gut hat eine Dimension
-- vorhergesagt? Rueckgabe: Trefferquote, Stichprobe und ob sie zaehlt.
function Analytics:DimensionPerformance(bucketName, key)
    local report = self:GetReport()
    local bucketTable = report[bucketName]
    local cell = bucketTable and bucketTable[key]
    if not cell or cell.n == 0 then return nil end
    return cell.hitRate, cell.n, not cell.lowSample
end
