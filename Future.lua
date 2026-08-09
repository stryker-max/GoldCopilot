local addonName, GCP = ...

GCP.Future = {}
local Future = GCP.Future

local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ---------------------------------------------------------------------------
-- FUTURE MARKET / CATALYST ENGINE (0.7.0)
--
-- 0.5 beantwortet: "Wie steht der Preis relativ zu seiner eigenen Historie?"
-- 0.6 beantwortet: "Ist daraus gerade eine Gold-Chance ableitbar?"
-- 0.7 beantwortet: "Welche bereits bekannten Veraenderungen im Spiel koennten
--                   die Nachfrage nach diesem Item veraendern?"
--
-- Was dieses Modul ausdruecklich NICHT tut:
--   * Es sagt keine Preise voraus. Nirgends steht eine Zielmarke in Gold.
--   * Es behauptet nichts ohne Herkunft. Jede Aussage der Wissensbasis traegt
--     ihre Provenance, und ohne die kommt sie dort gar nicht erst hinein.
--   * Es verwechselt Fakt und Modell nicht. "Der Schwarze Tempel oeffnet am
--     27.08." ist ein Fakt. "Das hebt die Nachfrage nach Urschatten" ist ein
--     Modell. Die Erklaerung sagt bei jeder Zeile, was von beidem sie ist.
--
-- Vier Kennzahlen, vier verschiedene Fragen:
--
--   Market Score (0.5)   Wie guenstig ist der Preis gemessen an der Historie?
--   Future Demand        Sprechen bekannte kommende Ereignisse fuer mehr
--                        Nachfrage - oder fuer mehr Angebot?
--   Hype Score           Ist genau das auf deinem Realm schon eingepreist?
--   Future Opportunity   Alles zusammen, als eine Rangfolge.
--
-- Der Hype Score ist die wichtigste Bremse des Moduls. Ohne ihn wuerde jede
-- bekannte Ankuendigung ewig als Kaufgrund gelten - auch dann noch, wenn der
-- Realm sie laengst dreifach bezahlt hat.
-- ---------------------------------------------------------------------------

Future.cache = nil
Future.graph = nil
Future.graphSignature = nil
Future.itemCache = {}
Future.itemCacheSignature = nil

local function config()
    return GCP.Constants.FUTURE
end

local function knowledge()
    return GCP.Knowledge
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- Saettigung: value / (value + half). Dieselbe Kurve wie in der Opportunity
-- Engine, aus demselben Grund - mehr ist besser, aber nicht linear, und es gibt
-- keine Obergrenze im Eingang, ab der die Rechnung kippt.
local function saturate(value, half)
    if type(value) ~= "number" or value <= 0 then return 0 end
    if type(half) ~= "number" or half <= 0 then return 1 end
    return value / (value + half)
end

local function isItemID(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

function Future:Now()
    if GCP.Market then return GCP.Market:Now() end
    if type(time) == "function" then
        local ok, now = pcall(time)
        if ok and type(now) == "number" then return now end
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- Phasen
-- ---------------------------------------------------------------------------

function Future:GetPhases()
    return knowledge():GetPhases()
end

-- Die hoechste Phase, die bereits laeuft.
function Future:GetCurrentPhase()
    local now = self:Now()
    local K = knowledge()
    local current = nil
    for _, phase in ipairs(K:GetPhases()) do
        if K:PhaseStatus(phase, now) == "live" then
            if not current or phase.order > current.order then current = phase end
        end
    end
    return current
end

-- Alles, was noch nicht laeuft - inklusive der Phasen ohne bekannten Termin.
-- Reihenfolge: erst die mit Termin (naechster zuerst), dann die ohne.
function Future:GetUpcomingPhases()
    local now = self:Now()
    local K = knowledge()
    local list = {}
    for _, phase in ipairs(K:GetPhases()) do
        local status = K:PhaseStatus(phase, now)
        if status ~= "live" then
            list[#list + 1] = phase
        end
    end
    table.sort(list, function(a, b)
        local aRelease, bRelease = a.release, b.release
        if (aRelease ~= nil) ~= (bRelease ~= nil) then return aRelease ~= nil end
        if aRelease and bRelease and aRelease ~= bRelease then return aRelease < bRelease end
        return a.order < b.order
    end)
    return list
end

-- Die naechste Phase, um die es geht. Bevorzugt eine mit bekanntem Termin -
-- eine Phase ohne Datum ist zwar bekannt, aber kein Zeitpunkt.
function Future:GetNextPhase()
    local upcoming = self:GetUpcomingPhases()
    return upcoming[1]
end

-- Zeitfenster einer Phase. Bewusst nicht "je naeher, desto besser": Kurz vor
-- Release ist die Ankuendigung meist laengst eingepreist, und danach entscheidet
-- nicht mehr die Erwartung, sondern das tatsaechliche Angebot.
function Future:PhaseTiming(phaseID, now)
    local K = knowledge()
    local phase = type(phaseID) == "table" and phaseID or K:GetPhase(phaseID)
    if not phase then
        return { zone = "UNKNOWN", status = "unknown" }
    end
    now = now or self:Now()
    local status = K:PhaseStatus(phase, now)
    local timing = {
        phase = phase,
        phaseID = phase.id,
        status = status,
        release = phase.release,
        zone = "UNKNOWN",
    }
    if type(phase.release) ~= "number" then
        -- Ohne Termin gibt es keine Zeitzone. Das ist kein Fehler, sondern die
        -- ehrliche Antwort - und die Rechnung gewichtet sie entsprechend.
        timing.zone = status == "live" and "POST_RELEASE" or "UNKNOWN"
        return timing
    end

    local T = config().TIMING
    local exactDays = (phase.release - now) / 86400
    local days = math.floor(exactDays)
    timing.daysUntil = days
    timing.exactDays = exactDays
    if days > T.EARLY_DAYS then
        timing.zone = "EARLY"
    elseif days >= T.ACCUMULATION_DAYS then
        timing.zone = "ACCUMULATION"
    elseif days >= T.PRE_RELEASE_DAYS then
        timing.zone = "PRE_RELEASE"
    elseif days >= T.RELEASE_DAYS then
        timing.zone = "RELEASE"
    else
        timing.zone = "POST_RELEASE"
    end
    return timing
end

function Future:TimingLabel(zone)
    return config().TIMING_LABEL[zone or "UNKNOWN"] or "unbekannt"
end

-- ---------------------------------------------------------------------------
-- DEPENDENCY GRAPH
--
-- Drei Quellen, eine Kantenliste:
--   1. Knowledge/Recipes.lua - kuratiert, mit Provenance, immer vorhanden.
--   2. Constants.CRAFT_COOLDOWNS - die Umwandlungen, die das Addon seit 0.3
--      ohnehin kennt.
--   3. Die tatsaechlich gescannten Rezepte des Spielers. Das ist die beste
--      Quelle, die es gibt: Sie kommt direkt aus dem Client.
--
-- Aufgebaut wird "Material -> Produkte", denn genau in diese Richtung laeuft
-- die Frage: Wofuer wird dieses Material gebraucht?
--
-- Der Graph wird nicht bei jedem Refresh neu gebaut, sondern haengt an einer
-- Signatur aus Wissensstand und Rezeptstand.
-- ---------------------------------------------------------------------------

local function addEdge(graph, edge)
    local G = config().GRAPH
    local list = graph.products[edge.from]
    if not list then
        list = {}
        graph.products[edge.from] = list
    end
    if #list >= G.MAX_EDGES_PER_NODE then
        graph.dropped = graph.dropped + 1
        return
    end
    -- Dieselbe Kante zweimal (kuratiert und gescannt) ist eine Kante. Die
    -- kuratierte kommt zuerst und gewinnt, weil sie Provenance mitbringt.
    local key = tostring(edge.from) .. ">" .. tostring(edge.to)
    if graph.seen[key] then return end
    graph.seen[key] = true
    list[#list + 1] = edge
    graph.edgeCount = graph.edgeCount + 1

    local mats = graph.materials[edge.to]
    if not mats then
        mats = {}
        graph.materials[edge.to] = mats
    end
    mats[#mats + 1] = edge
end

function Future:GraphSignature()
    return table.concat({
        tostring(knowledge().VERSION),
        tostring(GCP.Crafts and GCP.Crafts.revision or 0),
    }, "|")
end

function Future:BuildGraph()
    local graph = {
        products = {}, materials = {}, seen = {},
        edgeCount = 0, dropped = 0, sources = { knowledge = 0, cooldown = 0, scanned = 0 },
    }

    for _, edge in ipairs(knowledge().edges) do
        addEdge(graph, {
            from = edge.from, to = edge.to, quantity = edge.quantity,
            relation = edge.relation, recipe = edge.recipe,
            origin = "knowledge", sourceConfidence = edge.sourceConfidence,
        })
        graph.sources.knowledge = graph.sources.knowledge + 1
    end

    for _, craft in ipairs(GCP.Constants.CRAFT_COOLDOWNS or {}) do
        for _, mat in ipairs(craft.mats or {}) do
            addEdge(graph, {
                from = mat[1], to = craft.product, quantity = mat[2],
                relation = "conversion", recipe = craft.profession,
                origin = "cooldown", sourceConfidence = "historical",
            })
            graph.sources.cooldown = graph.sources.cooldown + 1
        end
    end

    if GCP.Crafts then
        local ok, recipes = pcall(GCP.Crafts.AllRecipes, GCP.Crafts)
        if ok and type(recipes) == "table" then
            for _, recipe in ipairs(recipes) do
                for _, mat in ipairs(recipe.mats or {}) do
                    if isItemID(mat[1]) and isItemID(recipe.product) then
                        addEdge(graph, {
                            from = mat[1], to = recipe.product, quantity = mat[2],
                            relation = "craft_material", recipe = recipe.name,
                            origin = "scanned", sourceConfidence = "official",
                        })
                        graph.sources.scanned = graph.sources.scanned + 1
                    end
                end
            end
        end
    end

    graph.seen = nil
    return graph
end

function Future:GetGraph()
    local signature = self:GraphSignature()
    if self.graph and self.graphSignature == signature then
        return self.graph
    end
    self.graph = self:BuildGraph()
    self.graphSignature = signature
    return self.graph
end

function Future:InvalidateGraph()
    self.graph = nil
    self.graphSignature = nil
end

-- Wofuer wird dieses Material gebraucht?
function Future:GetProductsOf(itemID)
    return self:GetGraph().products[itemID] or {}
end

-- Woraus besteht dieses Produkt?
function Future:GetMaterialsOf(itemID)
    return self:GetGraph().materials[itemID] or {}
end

-- ---------------------------------------------------------------------------
-- CATALYST-PROPAGATION
--
-- Ein Catalyst am Produkt gilt abgeschwaecht auch fuer dessen Zutaten:
--
--   Ebene 0   das Item selbst              100 %
--   Ebene 1   direkte Zutat                 70 %
--   Ebene 2   Zutat der Zutat               40 %
--   Ebene 3+  nicht mehr
--
-- Die Grenze ist der eigentliche Punkt. Ohne sie waere nach fuenf Ebenen jedes
-- Material der Scherbenwelt "extrem bullish", weil am Ende jeder Kette
-- Netherstoff und Adamantiterz stehen. Eine Aussage, die auf alles zutrifft,
-- ist keine.
--
-- Die Suche laeuft in Breite mit Besuchsliste: Umwandlungen wie Urluft -> Urfeuer
-- -> Urluft sind echte Kreise im Graphen, und ein Kreis darf keine
-- Endlosschleife werden.
-- ---------------------------------------------------------------------------

function Future:CollectCatalysts(itemID, now)
    if not isItemID(itemID) then return {} end
    local K = knowledge()
    local G = config().GRAPH
    local found = {}
    local seenCatalyst = {}
    local visited = { [itemID] = 0 }
    local frontier = { { itemID = itemID, depth = 0, via = nil } }

    while #frontier > 0 do
        local nextFrontier = {}
        for _, node in ipairs(frontier) do
            local catalysts = K:GetCatalystsForItem(node.itemID)
            if catalysts then
                for _, catalyst in ipairs(catalysts) do
                    if not seenCatalyst[catalyst.id] then
                        seenCatalyst[catalyst.id] = true
                        found[#found + 1] = {
                            catalyst = catalyst,
                            depth = node.depth,
                            via = node.via,
                            viaItemID = node.depth > 0 and node.itemID or nil,
                        }
                    end
                end
            end
            if node.depth < G.MAX_DEPTH then
                for _, edge in ipairs(self:GetProductsOf(node.itemID)) do
                    local target = edge.to
                    if visited[target] == nil then
                        visited[target] = node.depth + 1
                        nextFrontier[#nextFrontier + 1] = {
                            itemID = target,
                            depth = node.depth + 1,
                            via = edge,
                        }
                    end
                end
            end
        end
        frontier = nextFrontier
    end

    -- Gewichtung je Fund. Fuenf Faktoren, jeder mit eigener Begruendung:
    --   strength    wie wuchtig der Zusammenhang ist
    --   confidence  wie sicher wir uns beim Zusammenhang sind
    --   source      woher das Wissen stammt (offiziell schlaegt abgeleitet)
    --   timing      wie nah und wie brauchbar das Zeitfenster ist
    --   depth       wie weit weg das Item vom eigentlichen Ereignis steht
    local D = config().DEMAND
    now = now or self:Now()
    local timingCache = {}
    for _, entry in ipairs(found) do
        local catalyst = entry.catalyst
        local phaseID = catalyst.phase
        local timing = timingCache[phaseID or "?"]
        if not timing then
            timing = self:PhaseTiming(phaseID, now)
            timingCache[phaseID or "?"] = timing
        end
        entry.timing = timing
        entry.zone = timing.zone
        entry.daysUntil = timing.daysUntil
        entry.propagation = config().GRAPH.PROPAGATION[entry.depth] or 0
        entry.weight = catalyst.strength
            * (D.CONFIDENCE_WEIGHT[catalyst.confidence] or 0)
            * (D.SOURCE_WEIGHT[catalyst.sourceConfidence] or 0)
            * (D.TIMING_WEIGHT[timing.zone] or 0)
            * entry.propagation
        entry.direction = catalyst.direction
        entry.sign = knowledge().DIRECTIONS[catalyst.direction] or 0
    end

    table.sort(found, function(a, b)
        if a.weight ~= b.weight then return a.weight > b.weight end
        return a.catalyst.id < b.catalyst.id
    end)
    return found
end

function Future:GetCatalysts(itemID)
    local record = self:GetItemRecord(itemID)
    return record and record.catalysts or {}
end

-- ---------------------------------------------------------------------------
-- FUTURE DEMAND SCORE 0-100
--
--   50    keine bekannten Faktoren, oder Nachfrage und Angebot heben sich auf
--   > 50  bekannte Faktoren sprechen eher fuer zusaetzliche Nachfrage
--   < 50  bekannte Faktoren sprechen eher fuer Angebotsdruck oder nachlassende
--         relative Nachfrage
--
-- Die Rechnung in drei Schritten:
--
-- 1. Jeder Catalyst bekommt sein Gewicht (siehe CollectCatalysts) und landet
--    je nach Richtung auf der Nachfrage- oder der Angebotsseite.
--
-- 2. Beide Seiten werden mit abnehmendem Ertrag summiert: der staerkste Grund
--    zaehlt voll, der zweite zu 60 %, der dritte zu 36 % und so weiter. Zwei
--    unabhaengige Gruende sind mehr wert als einer - aber acht Gruende sind
--    nicht achtmal so viel wert, sondern nur etwas mehr als drei. Ohne diese
--    Daempfung gewinnt jedes Item mit vielen kleinen Verweisen gegen das eine
--    mit einem starken.
--
-- 3. Beide Summen laufen durch dieselbe Saettigungskurve und werden
--    gegeneinander verrechnet:
--       score = 50 + 50 * (saturate(Nachfrage) - saturate(Angebot))
--
-- Damit kann ein starker Angebots-Catalyst einen starken Nachfrage-Catalyst
-- neutralisieren - genau das passiert beim Leitmaterial einer neuen Phase, das
-- am Starttag gleichzeitig gebraucht wird und massenhaft hereinkommt.
--
-- Der Score ist KEIN Opportunity Score und erst recht keine Preisprognose.
-- ---------------------------------------------------------------------------

local function damped(weights, factor)
    table.sort(weights, function(a, b) return a > b end)
    local total, share = 0, 1
    for _, weight in ipairs(weights) do
        total = total + weight * share
        share = share * factor
    end
    return total
end

function Future:ComputeDemand(catalysts)
    local D = config().DEMAND
    local up, down = {}, {}
    local best, bestSupply = nil, nil
    for _, entry in ipairs(catalysts) do
        if entry.weight > 0 then
            if entry.sign > 0 then
                up[#up + 1] = entry.weight
                if not best or entry.weight > best.weight then best = entry end
            elseif entry.sign < 0 then
                down[#down + 1] = entry.weight
                if not bestSupply or entry.weight > bestSupply.weight then
                    bestSupply = entry
                end
            end
        end
    end

    local upTotal = damped(up, D.DIMINISHING)
    local downTotal = damped(down, D.DIMINISHING)
    local upEffect = saturate(upTotal, D.HALF)
    local downEffect = saturate(downTotal, D.HALF)
    local score = D.NEUTRAL + D.SPAN * (upEffect - downEffect)

    local leading = best or bestSupply
    return {
        score = clamp(math.floor(score + 0.5), 0, 100),
        upTotal = upTotal,
        downTotal = downTotal,
        upCount = #up,
        downCount = #down,
        hasCatalysts = (#up + #down) > 0,
        leading = leading,
        confidence = leading and leading.catalyst.confidence or nil,
        sourceConfidence = leading and leading.catalyst.sourceConfidence or nil,
        phase = leading and leading.catalyst.phase or nil,
        zone = leading and leading.zone or nil,
        daysUntil = leading and leading.daysUntil or nil,
    }
end

function Future:GetFutureDemandScore(itemID)
    local record = self:GetItemRecord(itemID)
    if not record then return config().DEMAND.NEUTRAL, nil end
    return record.demand.score, record.demand
end

-- ---------------------------------------------------------------------------
-- HYPE SCORE 0-100
--
-- Die Frage: Ist der bekannte Grund auf DEINEM Realm bereits eingepreist?
--
-- Ausschliesslich aus eigenen Marktdaten. Es gibt in einem Addon keine
-- Stimmungslage aus dem Internet, und eine erfundene waere schlimmer als keine.
--
-- Vier Signale, alle aus Market.lua:
--   Aufschlag zum 30-Tage-Median   (35 %)  wie teuer ist es gerade wirklich
--   Perzentil in der eigenen Reihe (25 %)  wo im eigenen Band steht der Preis
--   Momentum 7d gegen 30d          (25 %)  laeuft der Preis gerade nach oben
--   Volatilitaet                   (15 %)  wird der Markt unruhig
--
-- Alle vier zaehlen nur nach oben: Ein Preis unter seinem Median ist kein
-- negativer Hype, sondern schlicht keiner.
--
-- Ohne belastbare Historie gibt es keinen Hype Score, sondern nil. Aus drei
-- Messpunkten "kein Hype" zu folgern waere die gefaehrlichste Falschaussage,
-- die dieses Modul machen koennte - sie wuerde ausgerechnet dann Entwarnung
-- geben, wenn niemand etwas weiss.
-- ---------------------------------------------------------------------------

function Future:ComputeHype(stats)
    local H = config().HYPE
    if type(stats) ~= "table" then return nil end
    if (stats.snapshots or 0) < H.MIN_SNAPSHOTS or (stats.days or 0) < H.MIN_DAYS then
        return nil, { reason = "zu wenig Historie" }
    end
    local current, median30 = stats.current, stats.median30
    if not current or not median30 or median30 <= 0 then
        return nil, { reason = "kein belastbarer Median" }
    end

    local premium = (current - median30) / median30
    local premiumPart = clamp(premium / H.PREMIUM_SPAN, 0, 1)

    local percentile = stats.percentile or 50
    local percentilePart = clamp((percentile - 50) / 50, 0, 1)

    local momentumPart = 0
    if stats.median7 and stats.median7 > 0 then
        local momentum = (stats.median7 - median30) / median30
        momentumPart = clamp(momentum / H.MOMENTUM_SPAN, 0, 1)
    end

    local volatilityPart = 0
    if type(stats.volatility) == "number" and stats.volatility > 0 then
        volatilityPart = clamp(stats.volatility / H.VOLATILITY_CAP, 0, 1)
    end

    local raw = H.PREMIUM_WEIGHT * premiumPart
        + H.PERCENTILE_WEIGHT * percentilePart
        + H.MOMENTUM_WEIGHT * momentumPart
        + H.VOLATILITY_WEIGHT * volatilityPart

    return clamp(math.floor(100 * raw + 0.5), 0, 100), {
        premium = premium,
        premiumPart = premiumPart,
        percentilePart = percentilePart,
        momentumPart = momentumPart,
        volatilityPart = volatilityPart,
    }
end

function Future:GetHypeScore(itemID)
    local record = self:GetItemRecord(itemID)
    if not record then return nil end
    return record.hypeScore, record.hypeParts
end

-- ---------------------------------------------------------------------------
-- EINSTIEGSZONE UND "NICHT HINTERHERLAUFEN"
--
-- Keine willkuerliche Formel wie "Median minus 20 %". Der Anker ist das untere
-- Quartil der eigenen 30-Tage-Verteilung: ein Preis, den es auf diesem Realm
-- nachweislich gab, und zwar regelmaessig. Dazu der 7-Tage-Median als Bremse
-- nach unten - ist der Markt gerade gefallen, waere das alte Quartil eine Wette
-- auf eine Rueckkehr, fuer die es keinen Beleg gibt.
--
--   Basis    = min(unteres Quartil 30d, 7-Tage-Median)
--   Abschlag = Grundabschlag + Hype-Anteil
--   Einstieg = Basis * (1 - Abschlag)
--
-- Der Hype-Anteil ist der Kern: Je mehr die Erwartung schon im Preis steckt,
-- desto tiefer muss ein Einstieg liegen, um sie nicht mitzukaufen.
--
-- Reicht die Datenbasis nicht, gibt es nil - und die Oberflaeche schreibt
-- "noch keine belastbare Einstiegszone" statt einer Hausnummer.
-- ---------------------------------------------------------------------------

function Future:ComputeEntry(stats, hypeScore)
    local E = config().ENTRY
    if type(stats) ~= "table" then return nil end
    if (stats.snapshots or 0) < E.MIN_SNAPSHOTS or (stats.days or 0) < E.MIN_DAYS then
        return nil
    end
    local quartile = stats.q25 or stats.median30
    if not quartile or quartile <= 0 then return nil end
    local base = quartile
    if stats.median7 and stats.median7 > 0 and stats.median7 < base then
        base = stats.median7
    end

    local discount = E.BASE_DISCOUNT + E.HYPE_DISCOUNT * ((hypeScore or 0) / 100)
    local entry = math.floor(base * (1 - discount) + 0.5)
    if entry <= 0 then return nil end
    return entry, {
        base = base,
        quartile = stats.q25,
        median7 = stats.median7,
        discount = discount,
    }
end

-- Steht der Preis so weit ueber seiner eigenen Spanne, dass ein Einstieg jetzt
-- der Erwartung hinterherlaeuft?
function Future:ComputeDontChase(stats, hypeScore)
    local E = config().ENTRY
    if type(stats) ~= "table" or not stats.current then return false, nil end
    if stats.median30 and stats.median30 > 0 then
        local premium = (stats.current - stats.median30) / stats.median30
        if premium >= E.DONT_CHASE_PREMIUM then
            return true, string.format(
                "Der Preis liegt %.0f %% über dem 30-Tage-Median.", premium * 100)
        end
    end
    if type(stats.percentile) == "number" and stats.percentile >= E.DONT_CHASE_PERCENTILE then
        return true, string.format(
            "Der Preis steht im %d. Perzentil deiner eigenen Reihe.", stats.percentile)
    end
    if type(hypeScore) == "number" and hypeScore >= E.DONT_CHASE_HYPE then
        return true, "Preis und Momentum deuten darauf hin, dass der Catalyst "
            .. "bereits eingepreist wird."
    end
    return false, nil
end

-- ---------------------------------------------------------------------------
-- FUTURE OPPORTUNITY SCORE 0-100 (Investment Signal)
--
-- Ausdruecklich NICHT Market Score mal Future Demand. Ein Produkt zweier
-- Kennzahlen ist nicht nachvollziehbar: Es bestraft eine neutrale Zahl wie eine
-- schlechte, und es kann nicht sagen, welcher Faktor das Ergebnis getragen hat.
--
-- Stattdessen ein Aufbau um die Mitte, wie beim Market Score:
--
--   50                                   neutral: nichts spricht dafuer oder dagegen
--   + 0,50 * (FutureDemand - 50)         bis +25 / -25
--   + 0,35 * (MarketScore  - 50)         bis +17,5 / -17,5   (fehlt: zaehlt 50)
--   - 0,60 * max(0, Hype - 50)           bis -30
--   + Zeitfensterbonus                   -4 bis +6
--   - Volatilitaetsabschlag              bis -8
--   +- 8 * (LiquidityScore - 55)/50      nur ab Datenlage "mittel"  (0.8.0)
--   danach gedeckelt durch die Wissens-Confidence UND die Datenlage des Realms
--
-- Warum die persoenliche Liquiditaet nur acht Punkte wert ist und erst ab
-- mittlerer Datenlage ueberhaupt zaehlt: Future Demand ist Spielwissen - was
-- eine kommende Phase braucht, aendert sich nicht dadurch, dass ein einzelner
-- Spieler das Item bisher schlecht losgeworden ist. Der FUTURE DEMAND SCORE
-- SELBST BLEIBT DESHALB UNANGETASTET; die Liquiditaet faerbt nur das
-- Investment Signal ein, also die Frage "soll ich da rein?" - denn dort gehoert
-- sie hin: Eine richtige These nuetzt nichts, wenn man nicht wieder rauskommt.
-- Ohne belastbare eigene Daten passiert an dieser Stelle exakt nichts.
--
-- Warum der Hype so schwer wiegt: Er ist die einzige Groesse, die aus echten
-- Marktdaten sagt, ob die bekannte Geschichte schon bezahlt ist. Ein starker
-- Catalyst bei bereits gestiegenem Preis ist keine gute neue Position - er ist
-- die Position von jemand anderem.
--
-- Warum das Zeitfenster nur wenige Punkte wert ist: Naeher ist nicht besser.
-- Die Aufbauphase bekommt den groessten Bonus, das Releasefenster keinen, die
-- Zeit danach einen Abzug.
--
-- Die beiden Deckel: Ein Signal kann nie besser sein als das Wissen, auf dem es
-- beruht (Knowledge-Confidence), und nie besser als die Realm-Daten, gegen die
-- es geprueft wurde (Market-Confidence). Ohne Historie sind hoechstens 55
-- Punkte moeglich, egal wie stark der Catalyst ist.
-- ---------------------------------------------------------------------------

function Future:ComputeSignal(input)
    local S = config().SIGNAL
    local demandScore = input.futureDemandScore
    if type(demandScore) ~= "number" then demandScore = config().DEMAND.NEUTRAL end

    local marketScore = input.marketScore
    local marketKnown = type(marketScore) == "number"
    if not marketKnown then marketScore = S.NEUTRAL_MARKET_SCORE end

    local raw = S.BASE
        + S.DEMAND_WEIGHT * (demandScore - config().DEMAND.NEUTRAL)
        + S.MARKET_WEIGHT * (marketScore - S.NEUTRAL_MARKET_SCORE)

    local hypePenalty = 0
    if type(input.hypeScore) == "number" then
        hypePenalty = S.HYPE_WEIGHT * math.max(0, input.hypeScore - S.HYPE_NEUTRAL)
        raw = raw - hypePenalty
    end

    local timingBonus = S.TIMING_BONUS[input.zone or "UNKNOWN"] or 0
    raw = raw + timingBonus

    local volatilityPenalty = 0
    if type(input.volatility) == "number" and input.volatility > 0 then
        volatilityPenalty = S.VOLATILITY_PENALTY
            * math.min(input.volatility, S.VOLATILITY_CAP) / S.VOLATILITY_CAP
        raw = raw - volatilityPenalty
    end

    -- Persoenliche Liquiditaet. Der Schwellenwert ist eine Bedingung, keine
    -- Gewichtung: Unter "mittel" wird nicht schwach beruecksichtigt, sondern
    -- gar nicht. Drei Auktionen sind kein Urteil ueber eine Investmentthese.
    local liquidityAdjust = 0
    if type(input.liquidityScore) == "number"
        and GCP.Opportunity:ConfidenceRank(input.liquidityConfidence)
            >= GCP.Opportunity:ConfidenceRank(S.LIQUIDITY_MIN_CONFIDENCE) then
        liquidityAdjust = S.LIQUIDITY_POINTS * clamp(
            (input.liquidityScore - S.LIQUIDITY_NEUTRAL) / S.LIQUIDITY_SPAN, -1, 1)
        raw = raw + liquidityAdjust
    end

    local ceiling = 100
    if input.knowledgeConfidence then
        ceiling = math.min(ceiling, S.KNOWLEDGE_CAP[input.knowledgeConfidence] or 100)
    end
    ceiling = math.min(ceiling, S.MARKET_CAP[input.marketConfidence or "none"] or 100)

    return clamp(math.floor(math.min(raw, ceiling) + 0.5), 0, 100), {
        demand = S.DEMAND_WEIGHT * (demandScore - config().DEMAND.NEUTRAL),
        market = S.MARKET_WEIGHT * (marketScore - S.NEUTRAL_MARKET_SCORE),
        marketKnown = marketKnown,
        hypePenalty = hypePenalty,
        timingBonus = timingBonus,
        volatilityPenalty = volatilityPenalty,
        liquidityAdjust = liquidityAdjust,
        raw = raw,
        ceiling = ceiling,
    }
end

function Future:ScoreBand(score)
    if type(score) ~= "number" then return nil end
    for _, band in ipairs(config().BANDS) do
        if score >= band.min then return band.label, band.min end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Der vollstaendige Datensatz eines Items
-- ---------------------------------------------------------------------------

function Future:ItemCacheSignature()
    local db = GCP.db
    local watched = 0
    for _ in pairs((db and db.watchlist) or {}) do watched = watched + 1 end
    -- Die Zeitzone eines Catalysts wandert mit der Uhr; ohne den Stundenblock
    -- in der Signatur bliebe eine ACCUMULATION-Bewertung auch dann stehen, wenn
    -- der Release laengst vorbei ist.
    local hourBucket = math.floor(self:Now() / 3600)
    return table.concat({
        self:GraphSignature(),
        tostring(GCP.Market and GCP.Market.revision or 0),
        tostring(GCP.Ledger and GCP.Ledger.revision or 0),
        tostring(watched),
        tostring(hourBucket),
    }, "|")
end

function Future:Invalidate()
    self.cache = nil
    self.itemCache = {}
    self.itemCacheSignature = nil
    self:InvalidateGraph()
end

function Future:GetItemRecord(itemID)
    if not isItemID(itemID) then return nil end
    local signature = self:ItemCacheSignature()
    if self.itemCacheSignature ~= signature then
        self.itemCache = {}
        self.itemCacheSignature = signature
    end
    local cached = self.itemCache[itemID]
    if cached then return cached end

    local now = self:Now()
    local catalysts = self:CollectCatalysts(itemID, now)
    local demand = self:ComputeDemand(catalysts)

    local stats = GCP.Market and GCP.Market:GetMarketScore(itemID) or nil
    local hypeScore, hypeParts = self:ComputeHype(stats)
    local entry, entryParts = self:ComputeEntry(stats, hypeScore)
    local dontChase, dontChaseReason = self:ComputeDontChase(stats, hypeScore)

    -- Die persoenliche Handelsbilanz aus 0.8.0. Sie kommt hier als eigene
    -- Dimension dazu und veraendert weder Catalysts noch Demand.
    local liquidity = GCP.Ledger and GCP.Ledger:GetLiquidity(itemID) or nil

    local score, parts = nil, nil
    if demand.hasCatalysts or (stats and stats.score) then
        score, parts = self:ComputeSignal({
            futureDemandScore = demand.score,
            marketScore = stats and stats.score or nil,
            hypeScore = hypeScore,
            volatility = stats and stats.volatility or nil,
            zone = demand.zone,
            knowledgeConfidence = demand.confidence,
            marketConfidence = stats and stats.confidence or "none",
            liquidityScore = liquidity and liquidity.liquidityScore or nil,
            liquidityConfidence = liquidity and liquidity.confidence or nil,
        })
    end

    -- Einmal fragen, dreimal verwenden: GetItemInfo ist der teuerste Aufruf in
    -- dieser Schleife, und der Bericht laeuft ueber jedes bekannte Item.
    local name, _, quality, _, _, _, _, _, _, icon = GetItemInfoCompat(itemID)

    local record = {
        itemID = itemID,
        name = name or knowledge():ItemName(itemID),
        icon = icon,
        quality = quality,
        stats = stats,
        marketScore = stats and stats.score or nil,
        marketConfidence = stats and stats.confidence or "none",
        volatility = stats and stats.volatility or nil,
        catalysts = catalysts,
        demand = demand,
        futureDemandScore = demand.score,
        hypeScore = hypeScore,
        hypeParts = hypeParts,
        entryPrice = entry,
        entryParts = entryParts,
        dontChase = dontChase,
        dontChaseReason = dontChaseReason,
        futureOpportunityScore = score,
        scoreParts = parts,
        confidence = demand.confidence,
        sourceConfidence = demand.sourceConfidence,
        phase = demand.phase,
        daysUntilCatalyst = demand.daysUntil,
        timing = demand.zone,
        computedAt = now,

        -- Liquidity Brain (0.8.0). Gefuellt, WENN es eigene Verkaufsdaten zu
        -- diesem Item gibt - sonst weiter nil. profitVelocity bleibt hier
        -- grundsaetzlich nil: Eine Zukunftsposition hat noch keinen
        -- feststehenden Gewinn, durch den sich eine Rate teilen liesse.
        liquidity = liquidity,
        sellThrough = liquidity and liquidity.sellThrough or nil,
        expectedHours = liquidity and liquidity.expectedHours or nil,
        liquidityScore = liquidity and liquidity.liquidityScore or nil,
        liquidityConfidence = liquidity and liquidity.confidence or nil,
        profitVelocity = nil,
    }
    self.itemCache[itemID] = record
    return record
end

function Future:GetInvestmentSignal(itemID)
    return self:GetItemRecord(itemID)
end

-- Alles, was die Wissensbasis ueber ein Item weiss - ohne Bewertung.
function Future:GetItemKnowledge(itemID)
    if not isItemID(itemID) then return nil end
    local K = knowledge()
    local direct = K:GetCatalystsForItem(itemID)
    local materials = self:GetMaterialsOf(itemID)
    local products = self:GetProductsOf(itemID)
    if not direct and #materials == 0 and #products == 0 and not K:GetItem(itemID) then
        return nil
    end
    return {
        itemID = itemID,
        entry = K:GetItem(itemID),
        name = K:ItemName(itemID),
        catalysts = direct or {},
        materials = materials,
        products = products,
        knowledgeVersion = K.VERSION,
    }
end

-- ---------------------------------------------------------------------------
-- "WARUM?" - die Erklaerung
--
-- Strukturierte Gruende, keine fertige Textwand. Die Oberflaeche entscheidet,
-- was sie daraus macht; der Tooltip zeigt heute alles, eine spaetere Ansicht
-- vielleicht nur die Warnungen.
--
-- Jede Zeile sagt, was sie ist:
--   kind = "fact"   nachweisbarer Spielinhalt
--   kind = "model"  Einschaetzung dieses Addons
-- Modelloutput darf nie wie ein Blizzard-Fakt aussehen.
-- ---------------------------------------------------------------------------

local function line(text, kind, source)
    return { text = text, kind = kind or "model", source = source }
end

function Future:GetExplanation(itemID)
    local record = self:GetItemRecord(itemID)
    local result = { positive = {}, negative = {}, warnings = {}, facts = {} }
    if not record then return result end
    local K = knowledge()

    for _, entry in ipairs(record.catalysts) do
        local catalyst = entry.catalyst
        local phase = catalyst.phase and K:GetPhase(catalyst.phase)
        local prefix = ""
        if entry.depth > 0 then
            local viaName = entry.viaItemID
                and ((GetItemInfoCompat(entry.viaItemID)) or K:ItemName(entry.viaItemID)
                    or ("Item " .. entry.viaItemID))
                or "?"
            prefix = string.format("indirekt über %s: ", viaName)
        end
        local text = string.format("%s%s%s", prefix,
            phase and (phase.shortName .. " – ") or "", catalyst.reason)
        local bucket = entry.sign >= 0 and result.positive or result.negative
        bucket[#bucket + 1] = line(text, "model", catalyst.sourceName)

        if catalyst.fact then
            result.facts[#result.facts + 1] = line(catalyst.fact, "fact", catalyst.sourceName)
        end
    end

    -- Termin und Zeitfenster sind Fakten, sobald ein Datum bekannt ist.
    local phase = record.phase and K:GetPhase(record.phase)
    if phase then
        if phase.release then
            result.facts[#result.facts + 1] = line(string.format(
                "%s: %s öffnet in %d Tag(en) (%s).", phase.shortName, phase.name,
                record.daysUntilCatalyst or 0, date("%d.%m.%Y", phase.release)),
                "fact", phase.sourceName)
        else
            result.warnings[#result.warnings + 1] = line(string.format(
                "%s: %s – für die Anniversary-Realms ist noch kein Termin angekündigt.",
                phase.shortName, phase.name), "fact", phase.sourceName)
        end
    end

    if not record.demand.hasCatalysts then
        result.warnings[#result.warnings + 1] = line(
            "Kein belastbarer zukünftiger Nachfragegrund bekannt.", "model")
    end

    if record.hypeScore == nil then
        result.warnings[#result.warnings + 1] = line(
            "Für einen Hype-Score fehlt die Realm-Historie – ob der Catalyst bereits "
            .. "eingepreist ist, lässt sich noch nicht sagen.", "model")
    elseif record.hypeScore >= config().ENTRY.DONT_CHASE_HYPE then
        result.warnings[#result.warnings + 1] = line(string.format(
            "Hype %d/100: Der Preis ist bereits gestiegen – der Catalyst wird "
            .. "womöglich schon eingepreist.", record.hypeScore), "model")
    end

    if record.dontChase and record.dontChaseReason then
        result.warnings[#result.warnings + 1] = line(
            "Nicht hinterherlaufen – " .. record.dontChaseReason, "model")
    end

    if record.demand.downCount > 0 then
        result.warnings[#result.warnings + 1] = line(
            "Es gibt auch Gründe für zusätzliches Angebot – sie stehen oben "
            .. "unter den Gegenargumenten.", "model")
    end

    if record.marketConfidence == "none" or record.marketConfidence == "low" then
        result.warnings[#result.warnings + 1] = line(
            "Dünne Realm-Datenlage: Das Signal ist gedeckelt, bis mehr Preispunkte "
            .. "vorliegen.", "model")
    end

    -- Persoenliche Liquiditaet. Eine eigene Dimension neben dem Spielwissen -
    -- deshalb steht sie hier als eigene Zeile und nicht bei den Catalysts.
    local liquidity = record.liquidity
    if liquidity and liquidity.liquidityScore then
        local rank = GCP.Opportunity:ConfidenceRank(liquidity.confidence)
        local needed = GCP.Opportunity:ConfidenceRank(config().SIGNAL.LIQUIDITY_MIN_CONFIDENCE)
        local text = string.format(
            "Deine eigene Liquidität: %d/100 (Sell-through %s, %d Verkauf/Verkäufe, "
            .. "Datenlage %s).",
            liquidity.liquidityScore,
            liquidity.sellThrough
                and string.format("%.0f %%", liquidity.sellThrough * 100) or "unbekannt",
            liquidity.soldAuctions or 0,
            GCP.Market:ConfidenceLabel(liquidity.confidence))
        if rank < needed then
            result.warnings[#result.warnings + 1] = line(text .. " Zu wenig Daten – "
                .. "das Signal bleibt davon unberührt.", "model")
        else
            local bucket = liquidity.liquidityScore >= config().SIGNAL.LIQUIDITY_NEUTRAL
                and result.positive or result.negative
            bucket[#bucket + 1] = line(text, "model")
        end
    else
        result.warnings[#result.warnings + 1] = line(
            "Liquidität unbekannt – Gold Copilot hat für dieses Item noch keinen "
            .. "eigenen Verkauf gesehen. Das Signal bleibt davon unberührt.", "model")
    end

    result.warnings[#result.warnings + 1] = line(
        "Future Demand beschreibt bekannte Spielzusammenhänge und ist keine "
        .. "Preisgarantie.", "model")
    return result
end

-- ---------------------------------------------------------------------------
-- Bericht fuer den Zukunft-Tab
-- ---------------------------------------------------------------------------

function Future:KnownItems()
    return knowledge():AllKnownItems()
end

-- Alle Items, fuer die es ueberhaupt eine Zukunftsaussage geben kann: die Ziele
-- der Catalysts plus alles, was ueber den Graphen davon erreicht wird.
function Future:CandidateItems()
    local K = knowledge()
    local seen, list = {}, {}
    local function add(itemID)
        if isItemID(itemID) and not seen[itemID] then
            seen[itemID] = true
            list[#list + 1] = itemID
        end
    end
    local G = config().GRAPH
    for _, catalyst in ipairs(K.catalysts) do
        add(catalyst.itemID)
    end
    -- Von jedem Catalyst-Ziel die Zutaten bis zur Propagationsgrenze einsammeln.
    local frontier = {}
    for _, itemID in ipairs(list) do frontier[#frontier + 1] = itemID end
    for depth = 1, G.MAX_DEPTH do
        local nextFrontier = {}
        for _, itemID in ipairs(frontier) do
            for _, edge in ipairs(self:GetMaterialsOf(itemID)) do
                if not seen[edge.from] then
                    add(edge.from)
                    nextFrontier[#nextFrontier + 1] = edge.from
                end
            end
        end
        frontier = nextFrontier
    end
    return list
end

function Future:ComputeReport()
    local F = config()
    local now = self:Now()
    local rows = {}
    for _, itemID in ipairs(self:CandidateItems()) do
        local record = self:GetItemRecord(itemID)
        if record and record.demand.hasCatalysts then
            rows[#rows + 1] = record
        end
    end

    table.sort(rows, function(a, b)
        local aScore = a.futureOpportunityScore or -1
        local bScore = b.futureOpportunityScore or -1
        if aScore ~= bScore then return aScore > bScore end
        if a.futureDemandScore ~= b.futureDemandScore then
            return a.futureDemandScore > b.futureDemandScore
        end
        return (a.name or "") < (b.name or "")
    end)

    local matched = #rows
    if #rows > F.MAX_ROWS then
        for index = #rows, F.MAX_ROWS + 1, -1 do rows[index] = nil end
    end

    local nextPhase = self:GetNextPhase()
    local timing = nextPhase and self:PhaseTiming(nextPhase, now) or nil
    local graph = self:GetGraph()

    return {
        rows = rows,
        total = matched,
        listed = #rows,
        truncated = matched - #rows,
        currentPhase = self:GetCurrentPhase(),
        nextPhase = nextPhase,
        timing = timing,
        knowledgeVersion = knowledge().VERSION,
        knowledgeLabel = knowledge().VERSION_LABEL,
        knowledge = knowledge():Summary(),
        graph = { edges = graph.edgeCount, sources = graph.sources, dropped = graph.dropped },
        computedAt = now,
    }
end

function Future:BuildReport(force)
    local now = self:Now()
    local signature = self:ItemCacheSignature()
    local cache = self.cache
    if not force and cache and cache.signature == signature
        and (now - cache.computedAt) < config().CACHE_SECONDS then
        return cache.report
    end
    local report = self:ComputeReport()
    self.cache = { computedAt = now, signature = signature, report = report }
    -- Nur beim echten Neuberechnen protokollieren, nie bei einem Cache-Treffer.
    self:LogReport(report)
    return report
end

function Future:SummaryText(report)
    if not report or report.total == 0 then
        return "Gold Copilot kennt aktuell keinen belastbaren Zukunfts-Catalyst"
    end
    if report.total == 1 then
        return "Gold Copilot verfolgt 1 Item mit bekanntem Catalyst"
    end
    return string.format("Gold Copilot verfolgt %d Items mit bekannten Catalysts",
        report.total)
end

-- ---------------------------------------------------------------------------
-- Protokoll
--
-- Die Chancen-Historie aus 0.6 bekommt Future-Eintraege dazu, statt eine zweite
-- Tabelle zu eroeffnen: Es ist dieselbe Frage - was hat die Engine wann
-- behauptet, und stimmte es. Alte Eintraege bleiben unveraendert lesbar; die
-- neuen tragen type = "future" und stossen deshalb mit keinem der vier
-- Chancentypen zusammen.
--
-- Aufgeschrieben wird zurueckhaltend: nur belastbare Signale, dieselbe Zeile
-- hoechstens alle sechs Stunden, dazwischen nur bei deutlicher Bewegung.
-- ---------------------------------------------------------------------------

local HISTORY_TYPE = "future"

function Future:ShouldLog(record, now)
    local H = config().HISTORY
    if type(record) ~= "table" then return false end
    if type(record.futureOpportunityScore) ~= "number"
        or record.futureOpportunityScore < H.MIN_SIGNAL then
        return false
    end
    if (record.futureDemandScore or 0) < H.MIN_DEMAND then return false end
    if not record.demand or not record.demand.hasCatalysts then return false end

    local previous = GCP.Opportunity:LastLogged(HISTORY_TYPE, record.itemID)
    if not previous then return true end
    now = now or self:Now()
    if (now - (previous.timestamp or 0)) >= H.MIN_INTERVAL then return true end
    local delta = math.abs(record.futureOpportunityScore
        - (previous.futureOpportunityScore or 0))
    return delta >= H.SIGNAL_DELTA
end

function Future:LogReport(report, now)
    if not GCP.Opportunity then return 0 end
    local history = GCP.Opportunity:EnsureHistory()
    if not history or type(report) ~= "table" then return 0 end
    now = now or self:Now()
    local written = 0
    for _, record in ipairs(report.rows or {}) do
        if self:ShouldLog(record, now) then
            local catalystIDs = {}
            for _, entry in ipairs(record.catalysts) do
                catalystIDs[#catalystIDs + 1] = entry.catalyst.id
            end
            history[#history + 1] = {
                timestamp = now,
                type = HISTORY_TYPE,
                itemID = record.itemID,
                marketPrice = record.stats and record.stats.current or nil,
                marketScore = record.marketScore,
                futureDemandScore = record.futureDemandScore,
                hypeScore = record.hypeScore,
                futureOpportunityScore = record.futureOpportunityScore,
                confidence = record.confidence,
                phase = record.phase,
                daysUntilCatalyst = record.daysUntilCatalyst,
                catalystIDs = catalystIDs,
            }
            written = written + 1
        end
    end
    if written > 0 then
        GCP.Opportunity:PruneHistory(now)
    end
    return written
end

-- ---------------------------------------------------------------------------
-- Watchlist mit These
--
-- Die Watchlist aus 0.6 bleibt, wie sie ist. Sie bekommt nur optionale Felder
-- dazu: Phase, These, Wunsch-Einstieg, Notiz. Ein Eintrag aus 0.6 ohne diese
-- Felder funktioniert unveraendert weiter.
-- ---------------------------------------------------------------------------

function Future:Watch(itemID, thesis)
    if not GCP.Market then return false end
    local record = self:GetItemRecord(itemID)
    local meta = {
        reason = "future",
        phase = record and record.phase or nil,
        thesis = thesis,
        targetEntry = record and record.entryPrice or nil,
    }
    if GCP.Market:IsWatched(itemID) then
        GCP.Market:UpdateWatchMeta(itemID, meta)
        return false
    end
    return GCP.Market:RegisterWatchItem(itemID, "future", meta)
end

function Future:GetWatchlist()
    return GCP.Market and GCP.Market:GetWatchlist() or {}
end

-- ---------------------------------------------------------------------------
-- Anmeldung bei der Market Engine
--
-- Ohne Realm-Historie ist jede Zukunftsaussage nur die halbe Miete: Der Hype
-- Score braucht Preise, und die entstehen nur fuer beobachtete Items. Deshalb
-- meldet die Wissensbasis ihre Items an - und zwar jetzt, nicht wenn die Phase
-- laeuft. Wer erst am Releasetag anfaengt zu messen, hat nichts zu vergleichen.
-- ---------------------------------------------------------------------------

function Future:RegisterKnownItems()
    if not GCP.Market then return 0 end
    local registered = 0
    for _, itemID in ipairs(self:CandidateItems()) do
        if GCP.Market:RegisterItem(itemID, "Zukunft") then
            registered = registered + 1
        end
    end
    return registered
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    if not GCP.db then GCP:EnsureDB() end
    Future:RegisterKnownItems()
end)

-- Auch ohne Login-Ereignis (Tests, Neuladen der Oberflaeche) soll die
-- Anmeldung passiert sein, sobald das Modul geladen ist.
Future:RegisterKnownItems()
