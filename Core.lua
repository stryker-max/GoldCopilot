local addonName, GCP = ...

_G.GoldCopilot = GCP

GCP.addonName = addonName
GCP.initialized = false

function GCP:Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(GCP.Constants.COLOR_PREFIX .. tostring(message))
    end
end

-- Heutiger Kalendertag als Schluessel fuer Goldverlauf und Preishistorie.
-- Beides sind Zeitreihen ueber Kalendertage - dort ist die lokale Uhr richtig,
-- und beide bleiben bewusst vom Serverreset unberuehrt.
function GCP:Today()
    return date("%Y-%m-%d")
end

-- Schluessel der laufenden Daily-Periode - der Taktgeber des Tagesplans.
-- Dessen Inhalt (Dailies, Questflags, Berufs-Cooldowns) wird nicht um lokale
-- Mitternacht neu, sondern am WoW-Daily-Reset: Ein Reset um 0 Uhr wuerde die
-- Checkliste mitten in der Abendsitzung leeren und danach abgegebene Dailies
-- wieder als offen zeigen.
--
-- GetQuestResetTime liefert die Sekunden bis zum naechsten Reset. Der daraus
-- errechnete Reset-Zeitpunkt ist waehrend einer Periode konstant und springt
-- beim Reset um genau einen Tag weiter - damit taugt er direkt als Schluessel.
-- Auf volle Minuten gerundet, damit der Sekundenjitter der API nicht
-- durchschlaegt, und in UTC formatiert, damit eine Sommerzeitumstellung keinen
-- Reset vortaeuscht. Ohne die API bleibt es beim lokalen Kalendertag.
function GCP:ResetPeriodKey()
    if type(GetQuestResetTime) == "function" then
        local ok, secondsLeft = pcall(GetQuestResetTime)
        if ok and type(secondsLeft) == "number"
            and secondsLeft > 0 and secondsLeft <= 86400 then
            local resetAt = math.floor((time() + secondsLeft) / 60 + 0.5) * 60
            return "reset:" .. date("!%Y-%m-%d %H:%M", resetAt)
        end
    end
    return self:Today()
end

function GCP:EnsureDB()
    GoldCopilotDB = GoldCopilotDB or {}
    local db = GoldCopilotDB
    db.version = GCP.Constants.VERSION
    db.options = db.options or {}
    if db.options.priceSource == nil then db.options.priceSource = "auto" end
    if db.options.hideBound == nil then db.options.hideBound = false end
    if db.options.minRoadmapValue == nil then
        db.options.minRoadmapValue = GCP.Constants.MIN_ROADMAP_VALUE
    end
    if db.options.dailyGoal == nil then
        db.options.dailyGoal = GCP.Constants.DEFAULT_DAILY_GOAL
    end
    if db.options.keepConsumables == nil then db.options.keepConsumables = true end
    -- Die Chancen-Filter aus 0.6.0 stehen bewusst neben minRoadmapValue statt
    -- darin: Der Tagesplan filtert Aufgaben nach Ertrag, die Chancenliste
    -- filtert Kapitaleinsatz. Wer den einen aendert, meint nicht den anderen.
    if db.options.opportunityMinProfit == nil then
        db.options.opportunityMinProfit = GCP.Constants.OPPORTUNITY.DEFAULT_MIN_PROFIT
    end
    if db.options.opportunityMinROI == nil then
        db.options.opportunityMinROI = GCP.Constants.OPPORTUNITY.DEFAULT_MIN_ROI
    end
    db.options.ignored = db.options.ignored or {}
    db.questGold = db.questGold or {}
    db.roadmap = db.roadmap or {}
    db.roadmap.checked = db.roadmap.checked or {}
    db.roadmap.baseline = db.roadmap.baseline or {}
    db.goldHistory = db.goldHistory or {}
    db.priceHistory = db.priceHistory or {}
    -- 0.6.0: Watchlist und Chancen-Protokoll. Beide legen sich leer an und
    -- ersetzen nichts - eine Datenbank aus 0.3, 0.4 oder 0.5 bleibt vollstaendig.
    db.watchlist = db.watchlist or {}
    db.opportunityHistory = db.opportunityHistory or {}
    -- 0.8.0: Sortierung der Chancenliste und des Handel-Tabs. Beides sind
    -- Ansichtseinstellungen, keine Filter - sie blenden nichts aus.
    if db.options.opportunitySort == nil then db.options.opportunitySort = "score" end
    if db.options.ledgerSort == nil then db.options.ledgerSort = "liquidity" end
    -- 0.9.0: Guide, Navigation und Zielmodus. Alle Voreinstellungen sind
    -- zurueckhaltend: Der Pfeil ist an, das automatische Einfuegen neuer
    -- Chancen in eine laufende Route ausdruecklich aus.
    if db.options.guideAutoInsert == nil then db.options.guideAutoInsert = false end
    if db.options.guideArrow == nil then db.options.guideArrow = true end
    if db.options.guideViewer == nil then db.options.guideViewer = true end
    if db.options.navigationTomTom == nil then db.options.navigationTomTom = false end
    if db.options.goalAmount == nil then
        db.options.goalAmount = GCP.Constants.GUIDE.DEFAULT_GOAL
    end
    if db.options.goalMinutes == nil then db.options.goalMinutes = 60 end
    if db.options.goalRisk == nil then db.options.goalRisk = "medium" end
    if type(db.options.goalTypes) ~= "table" then
        db.options.goalTypes = {
            craft = true, conversion = true, resale = true,
            disenchant = true, farm = true, future = true,
        }
    end
    self.db = db
    self:ResetRoadmapIfNewDay()
    -- Die Markthistorie aus 0.5.0 legt sich selbst an und uebernimmt einmalig
    -- die vorhandene Tages-Preishistorie. Beides passiert erst hier, weil es
    -- self.db braucht; db.priceHistory bleibt dabei unveraendert bestehen.
    if GCP.Market then
        GCP.Market:EnsureStore()
        GCP.Market:ImportLegacyHistory()
    end
    -- Die Handelsbilanz aus 0.8.0 legt sich leer an und ersetzt nichts. Eine
    -- Datenbank aus 0.3 bis 0.7 bleibt vollstaendig; sie hat schlicht noch
    -- keine Verkaufsdaten, und dann sagt das Addon das auch so.
    if GCP.Ledger then
        GCP.Ledger:EnsureStore()
        GCP.Ledger:Prune(nil, true)
    end
    if GCP.Opportunity then
        GCP.Opportunity:PruneHistory()
        GCP.Opportunity:MatchHistoryOutcomes()
        GCP.Opportunity:Invalidate()
    end
    -- Die Wissensbasis aus 0.7.0 legt nichts in den SavedVariables an: Sie wird
    -- mit dem Addon ausgeliefert. Nur ihre Items werden zur Beobachtung
    -- angemeldet, damit ueberhaupt eine Realm-Historie entsteht, bevor die
    -- naechste Phase da ist.
    if GCP.Future then
        GCP.Future:Invalidate()
        GCP.Future:RegisterKnownItems()
    end
    -- Das Capital Brain aus 0.9.0 legt seine Reserve-Einstellung und die
    -- Positions-Provenance leer an. Ohne beides rechnet es weiter - dann steht
    -- an den Positionen "Einstand unbekannt", und das ist die richtige Antwort.
    if GCP.Capital then
        GCP.Capital:EnsureStore()
        GCP.Capital:PruneMeta()
        GCP.Capital:Invalidate()
    end
    -- Navigation lernt Orte aus den eigenen Besuchen. Der Speicher legt sich
    -- leer an, und ohne einen einzigen Besuch zeigt der Guide Textanweisungen
    -- statt eines Pfeils - das ist der Normalfall beim ersten Start.
    if GCP.Navigation then
        GCP.Navigation:EnsureStore()
        GCP.Navigation:InstallEvents()
    end
    -- Die Guide Engine haelt ihren Zustand in den SavedVariables: Ein /reload
    -- mitten in einer Route darf weder den Fortschritt noch die bereits
    -- erledigten Schritte kosten.
    if GCP.Guide then
        GCP.Guide:EnsureStore()
        GCP.Guide:InstallEvents()
        GCP.Guide:Restore()
    end
    return db
end

-- db.roadmap.day haelt weiterhin den Schluessel der Periode; seit 0.4.0 ist das
-- der Reset-Zeitraum statt des Kalendertags. Alte gespeicherte Werte passen
-- schlicht auf keine Periode mehr und loesen genau einen Reset aus.
function GCP:ResetRoadmapIfNewDay()
    local period = self:ResetPeriodKey()
    if self.db.roadmap.day ~= period then
        self.db.roadmap.day = period
        self.db.roadmap.checked = {}
        -- Die Baselines sind die Bestaende bei der ersten Plan-Erstellung der
        -- Periode; daran erkennt der Plan spaeter von selbst erledigte Aufgaben.
        self.db.roadmap.baseline = {}
    end
end

-- Haelt je Kalendertag den hoechsten gesehenen Goldstand fest. Accountweit,
-- sofern Syndicator die anderen Charaktere kennt; sonst nur der eigene.
function GCP:RecordGold()
    if not self.db then return end
    local total = GetMoney() or 0
    local ok, sum = pcall(function()
        if not (Syndicator and Syndicator.API) then return nil end
        local mine = Syndicator.API.GetCurrentCharacter()
        local accountSum = 0
        for _, name in ipairs(Syndicator.API.GetAllCharacters() or {}) do
            if name ~= mine then
                local char = Syndicator.API.GetByCharacterFullName(name)
                local money = char and char.money or (char and char.details and char.details.money)
                if type(money) == "number" then
                    accountSum = accountSum + money
                end
            end
        end
        return accountSum
    end)
    if ok and type(sum) == "number" then
        total = total + sum
    end
    local today = self:Today()
    local previous = self.db.goldHistory[today]
    if not previous or total > previous then
        self.db.goldHistory[today] = total
    end
    -- Der Verlauf soll die SavedVariables nicht endlos fuellen: 120 Tage reichen
    -- fuer jede Trendanzeige.
    local cutoff = date("%Y-%m-%d", time() - 120 * 86400)
    for day in pairs(self.db.goldHistory) do
        if day < cutoff then
            self.db.goldHistory[day] = nil
        end
    end
end

-- Nach einem AH-Besuch sind die Scanpreise der Preisquelle so frisch wie nie -
-- genau dann lohnt sich ein weiterer Schnappschuss fuer die Preishistorie.
-- Aufgezeichnet wird bewusst nur beim Verlassen des Auktionshauses, nicht bei
-- jeder einzelnen Auktion: Ein vollstaendiger Durchlauf ueber alle beobachteten
-- Items waehrend des Einstellens waere reine Beschaeftigungstherapie.
-- Die Drosselung faengt mehrfaches Auf- und Zumachen ab.
local AUCTION_RECORD_COOLDOWN = 60
local lastAuctionRecord = nil

function GCP:RecordPricesAfterAuction()
    if not self.db then return false end
    local now = (type(GetTime) == "function" and GetTime()) or 0
    if lastAuctionRecord and (now - lastAuctionRecord) < AUCTION_RECORD_COOLDOWN then
        return false
    end
    lastAuctionRecord = now
    self.Prices:RecordObservedPrices()
    if self.UI then self.UI:RefreshIfShown() end
    return true
end

-- Die Markthistorie haengt bevorzugt am Auctionator-Callback. Der hier bleibt
-- als Rueckfall bestehen: Ohne Auctionator, mit einer Fassung ohne die API oder
-- wenn die Registrierung fehlschlaegt, ist das Schliessen des Auktionshauses
-- weiterhin der Zeitpunkt mit den frischesten Preisen. Doppelt gemeldet schadet
-- nicht - Debounce und 30-Minuten-Fenster fangen das ab.
function GCP:NotifyMarketOfFreshPrices(reason)
    if not (self.Market and self.db) then return false end
    return self.Market:OnDatabaseUpdate(reason or "Auktionshaus")
end

-- Berufe und Sammelskills aus dem Fertigkeitenfenster; Classic kennt kein
-- GetProfessions. Rueckgabe: Skillname -> Rang.
function GCP:GetKnownSkills()
    local skills = {}
    if type(GetNumSkillLines) ~= "function" then return skills end
    for index = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(index)
        if name and not isHeader then
            skills[name] = rank or 0
        end
    end
    return skills
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_MONEY")
-- AUCTION_HOUSE_CLOSED gibt es in TBC Anniversary; sollte eine Clientfassung
-- den Namen nicht kennen, wirft RegisterEvent - der Rest des Addons darf davon
-- nicht mitgerissen werden.
pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_HOUSE_CLOSED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        GCP:EnsureDB()
        GCP.initialized = true
    elseif event == "PLAYER_LOGIN" then
        if not GCP.db then GCP:EnsureDB() end
        GCP:RecordGold()
        GCP.Prices:RecordObservedPrices()
        GCP:Print("bereit. /gold öffnet deinen Gold-Berater.")
    elseif event == "PLAYER_MONEY" then
        if GCP.db then GCP:RecordGold() end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        GCP:RecordPricesAfterAuction()
        GCP:NotifyMarketOfFreshPrices("Auktionshaus geschlossen")
    end
end)

-- Diagnose der Market Engine: was wird beobachtet, wie viel liegt da, wie alt
-- ist es und was kostet das an Dateigroesse.
function GCP:PrintMarketStats()
    local Market = self.Market
    if not Market then return end
    local overview = Market:GetOverview()
    self:Print(string.format("Tracked items: %d", overview.tracked))
    self:Print(string.format("Market snapshots: %s (%d Items mit Historie)",
        Market:FormatCount(overview.snapshots), overview.itemsWithHistory))
    if overview.oldest then
        self:Print("Oldest snapshot: " .. date("%Y-%m-%d %H:%M", overview.oldest))
        self:Print("Newest snapshot: " .. date("%Y-%m-%d %H:%M", overview.newest))
        self:Print(string.format("History span: %d Tag(e)", overview.spanDays))
    else
        self:Print("Oldest snapshot: noch keiner – Gold Copilot lernt deinen Realm.")
    end
    self:Print(string.format("Watchlist: %d Item(s)", Market:CountWatchItems()))
    self:Print("DB estimate: ~" .. Market:FormatBytes(Market:EstimateBytes()))
    self:Print("Auctionator-Callback: " .. (overview.callback
        and "aktiv (RegisterForDBUpdate)"
        or "nicht verfügbar – Rückfall auf AUCTION_HOUSE_CLOSED"))
end

-- Diagnose der Handelsbilanz: Was wurde erfasst, woher kommt es, wie viel
-- kostet es an Dateigroesse - und ob die beiden Erfassungswege ueberhaupt
-- laufen. Ein stiller Hook, der nie eingehaengt wurde, waere sonst nicht zu
-- bemerken.
function GCP:PrintLedgerStats()
    local Ledger = self.Ledger
    if not Ledger then return end
    local overview = Ledger:GetOverview()
    self:Print(string.format("Handelsereignisse: %s (%d Item(s))",
        GCP.Market:FormatCount(overview.events), overview.items))
    if overview.oldest then
        self:Print("Ältestes Ereignis: " .. date("%Y-%m-%d %H:%M", overview.oldest))
        self:Print("Jüngstes Ereignis: " .. date("%Y-%m-%d %H:%M", overview.newest))
    else
        self:Print("Noch kein Handel erfasst – Gold Copilot lernt aus deinen "
            .. "Verkäufen, sobald die ersten Auktionen durchlaufen.")
    end
    self:Print(string.format("Offene Einstellungen: %d", overview.openPostings))
    self:Print("Einstell-Hook (PostAuction): " .. (overview.hooked
        and "aktiv" or "nicht eingehängt – Verkaufsdauer bleibt unbekannt"))
    self:Print("Briefkasten-Abgleich: " .. (overview.mailScanAt
        and ("zuletzt " .. date("%Y-%m-%d %H:%M", overview.mailScanAt))
        or "noch nicht gelaufen – Briefkasten einmal öffnen"))
    self:Print("DB estimate: ~" .. GCP.Market:FormatBytes(Ledger:EstimateBytes()))
    local week = Ledger:GetGlobalStats(7)
    self:Print(string.format("7 Tage: %s Umsatz netto · %d Verkauf/Verkäufe · %d Ablauf/Abläufe",
        GCP.Prices:FormatGold(week.revenueNet), week.sales, week.expiries))
    self:Print("Alle Handelsdaten bleiben lokal in deinen SavedVariables.")
end

-- Diagnose der Wissensbasis: Wie alt ist das Wissen, wie viel steht drin, und
-- was hat die Pruefung verworfen? Ein verworfener Eintrag ist kein Drama, aber
-- er soll auffindbar sein und nicht still verschwinden.
function GCP:PrintKnowledgeStats()
    local Knowledge = self.Knowledge
    if not Knowledge then return end
    local summary = Knowledge:Summary()
    self:Print("Wissensstand: " .. Knowledge.VERSION_LABEL)
    self:Print(string.format("Phasen: %d · Catalysts: %d · Rezeptkanten: %d · Items: %d",
        summary.phases, summary.catalysts, summary.edges, summary.items))
    if self.Future then
        local current = self.Future:GetCurrentPhase()
        local nextPhase = self.Future:GetNextPhase()
        self:Print("Aktuelle Phase: " .. (current and current.name or "unbekannt"))
        if nextPhase then
            local timing = self.Future:PhaseTiming(nextPhase)
            if timing.daysUntil then
                self:Print(string.format("Nächste Phase: %s in %d Tag(en)",
                    nextPhase.name, timing.daysUntil))
            else
                self:Print("Nächste Phase: " .. nextPhase.name
                    .. " – Termin noch nicht angekündigt")
            end
        end
        local graph = self.Future:GetGraph()
        self:Print(string.format("Dependency Graph: %d Kanten (%d aus der Wissensbasis, "
            .. "%d aus Umwandlungen, %d aus deinen gescannten Rezepten)",
            graph.edgeCount, graph.sources.knowledge, graph.sources.cooldown,
            graph.sources.scanned))
    end
    if summary.rejected > 0 then
        self:Print(string.format("Verworfene Wissenseinträge: %d", summary.rejected))
        for _, entry in ipairs(Knowledge.rejected) do
            self:Print(string.format("  %s %s – %s", entry.kind, entry.id, entry.reason))
        end
    end
end

SLASH_GOLDCOPILOT1 = "/gold"
SLASH_GOLDCOPILOT2 = "/goldcopilot"
SlashCmdList["GOLDCOPILOT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if not GCP.db then GCP:EnsureDB() end
    if msg == "reset" then
        GCP.db.roadmap.day = nil
        GCP:ResetRoadmapIfNewDay()
        GCP:Print("Tagesplan zurückgesetzt.")
        if GCP.UI then GCP.UI:Refresh() end
    elseif msg == "quelle" or msg == "source" then
        local source = GCP.Prices:GetActiveSourceLabel()
        GCP:Print("aktive Preisquelle: " .. source)
    elseif msg == "marketstats" then
        GCP:PrintMarketStats()
    elseif msg == "chancen" or msg == "opportunities" then
        if GCP.UI then
            GCP.UI:Toggle()
            if GCP.UI.frame and GCP.UI.frame:IsShown() then
                GCP.UI:SelectTab("chancen")
            end
        end
    elseif msg == "zukunft" or msg == "future" then
        if GCP.UI then
            GCP.UI:Toggle()
            if GCP.UI.frame and GCP.UI.frame:IsShown() then
                GCP.UI:SelectTab("zukunft")
            end
        end
    elseif msg == "handel" or msg == "ledger" then
        if GCP.UI then
            GCP.UI:Toggle()
            if GCP.UI.frame and GCP.UI.frame:IsShown() then
                GCP.UI:SelectTab("handel")
            end
        end
    elseif msg == "wissen" or msg == "knowledge" then
        GCP:PrintKnowledgeStats()
    elseif msg == "ledgerstats" then
        GCP:PrintLedgerStats()
    elseif msg == "ledgerreset" then
        -- Zweistufig wie beim Marktreset: Persoenliche Handelsdaten lassen
        -- sich nicht wiederbeschaffen.
        GCP:Print("löscht deine gesamte Handelsbilanz (nur sie – Markthistorie, "
            .. "Optionen, Goldverlauf und Beobachtungsliste bleiben).")
        GCP:Print("Zum Bestätigen: |cffd9a834/gold ledgerreset confirm|r")
    elseif msg == "ledgerreset confirm" then
        local removed = GCP.Ledger and GCP.Ledger:Reset() or 0
        GCP:Print(string.format("Handelsbilanz gelöscht (%s Ereignisse). "
            .. "Alle anderen Daten sind unberührt.",
            GCP.Market:FormatCount(removed)))
        if GCP.UI then GCP.UI:RefreshIfShown() end
    elseif msg == "watchlist" then
        local list = GCP.Market and GCP.Market:GetWatchlist() or {}
        if #list == 0 then
            GCP:Print("Beobachtungsliste leer – Rechtsklick auf eine Zeile im "
                .. "Markt- oder Chancen-Tab nimmt ein Item auf.")
        else
            GCP:Print(string.format("Beobachtungsliste (%d):", #list))
            for _, entry in ipairs(list) do
                local name = (GetItemInfo and GetItemInfo(entry.itemID)) or ("Item " .. entry.itemID)
                GCP:Print(string.format("  %s – %s", name, entry.reason or "manuell"))
            end
        end
    elseif msg == "marketreset" then
        -- Zweistufig mit Absicht: Ein Vertipper darf keine Wochen Realm-Daten
        -- kosten.
        GCP:Print("löscht die gesamte Markthistorie (nur sie – Optionen, "
            .. "Goldverlauf, Rezepte und Preisverlauf bleiben).")
        GCP:Print("Zum Bestätigen: |cffd9a834/gold marketreset confirm|r")
    elseif msg == "marketreset confirm" then
        local removed = GCP.Market and GCP.Market:Reset() or 0
        GCP:Print(string.format("Markthistorie gelöscht (%s Preispunkte). "
            .. "Alle anderen Daten sind unberührt.",
            GCP.Market and GCP.Market:FormatCount(removed) or "0"))
        if GCP.UI then GCP.UI:RefreshIfShown() end
    else
        if GCP.UI then
            GCP.UI:Toggle()
        end
    end
end
