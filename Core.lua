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

-- ---------------------------------------------------------------------------
-- REALM- UND FRAKTIONSTRENNUNG (0.9.0)
--
-- GoldCopilotDB ist accountweit. Das ist fuer Optionen und den Goldverlauf
-- richtig - und fuer Marktdaten falsch: Ein Auktionshaus der Horde auf Realm A
-- hat mit dem der Allianz auf Realm B nichts zu tun. Bis 0.8 lagen beide im
-- selben Topf; ab 0.9 bekommt jede Kombination aus Realm und Fraktion ihren
-- eigenen Speicher.
--
--   db.profiles = {
--       ["Blackrock|Horde"] = { marketHistory = ..., ledger = ..., ... },
--       ["Blackrock|Alliance"] = { ... },
--   }
--
-- MIGRATION: Die vorhandenen Daten wandern EINMAL in das Profil des
-- Charakters, mit dem zuerst eingeloggt wird. Das ist die einzige Zuordnung,
-- die sich belegen laesst - woher die Daten wirklich stammen, weiss niemand.
-- Sie werden dabei verschoben, nicht kopiert: Nichts geht verloren, und nichts
-- liegt doppelt in der Datei.
--
-- WAS ACCOUNTWEIT BLEIBT: Optionen, Goldverlauf, gelernte Quest-Betraege,
-- gescannte Rezepte und der Tagesplan. Nichts davon ist eine Marktaussage.
-- ---------------------------------------------------------------------------

GCP.PROFILE_VERSION = 1

-- Die Speicher, die zu genau einem Realm und einer Fraktion gehoeren.
GCP.PROFILE_STORES = {
    "marketHistory", "marketDepth", "marketProbes", "priceHistory", "watchlist",
    "ledger", "opportunityHistory", "capital", "farm", "income", "activity",
    "personal", "calibration", "guide",
}

function GCP:ProfileKey()
    local realm = "?"
    if type(GetRealmName) == "function" then
        local ok, value = pcall(GetRealmName)
        if ok and type(value) == "string" and value ~= "" then realm = value end
    end
    local faction = "?"
    if type(UnitFactionGroup) == "function" then
        local ok, value = pcall(UnitFactionGroup, "player")
        if ok and type(value) == "string" and value ~= "" then faction = value end
    end
    return realm .. "|" .. faction
end

-- Der Speicher dieses Realms. Gecacht am Schluessel, weil er in heissen
-- Schleifen liegt (jede Preisabfrage geht hier durch) - Realm und Fraktion
-- aendern sich innerhalb einer Sitzung nicht.
function GCP:Profile()
    local db = GoldCopilotDB
    if type(db) ~= "table" then return {} end
    local key = self:ProfileKey()
    if self.profileCache and self.profileKey == key
        and db.profiles and db.profiles[key] == self.profileCache then
        return self.profileCache
    end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    local profile = db.profiles[key]
    if type(profile) ~= "table" then
        profile = { key = key, createdAt = (type(time) == "function" and time()) or 0 }
        db.profiles[key] = profile
    end
    -- Die Grundstrukturen legen sich leer an; alles Weitere machen die Module.
    if type(profile.priceHistory) ~= "table" then profile.priceHistory = {} end
    if type(profile.watchlist) ~= "table" then profile.watchlist = {} end
    if type(profile.opportunityHistory) ~= "table" then profile.opportunityHistory = {} end
    self.profileCache = profile
    self.profileKey = key
    return profile
end

function GCP:ProfileCount()
    local db = GoldCopilotDB
    if type(db) ~= "table" or type(db.profiles) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(db.profiles) do count = count + 1 end
    return count
end

function GCP:MigrateProfiles()
    local db = GoldCopilotDB
    if type(db) ~= "table" then return false end
    if db.profileVersion == self.PROFILE_VERSION then return false end
    local profile = self:Profile()
    local moved = 0
    for _, key in ipairs(self.PROFILE_STORES) do
        if db[key] ~= nil then
            -- Nur uebernehmen, wenn das Profil dort noch nichts hat: Ein
            -- zweiter Durchlauf darf frische Daten nicht ueberschreiben.
            if profile[key] == nil or next(profile[key]) == nil then
                profile[key] = db[key]
                moved = moved + 1
            end
            db[key] = nil
        end
    end
    db.profileVersion = self.PROFILE_VERSION
    return true, moved
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
    -- 1.0.0-beta.3: Der Plausibilitaetsfilter ist voreingestellt AN. Eine
    -- Chance, deren Verkaufspreis auf einer einzelnen Fantasie-Auktion beruht,
    -- ist keine Chance - und wer sie trotzdem sehen will, schaltet ihn ab.
    if db.options.hideImplausible == nil then db.options.hideImplausible = true end
    -- Stueckzahl je Position: nil heisst "automatisch" (belegabhaengiger
    -- Deckel), eine Zahl ist eine harte Obergrenze, 0 schaltet ihn ab.
    if db.options.maxUnitsPerPosition == nil then
        db.options.maxUnitsPerPosition = "auto"
    end
    db.options.ignored = db.options.ignored or {}
    -- 1.0.0-beta.4: Abgelehnte Items. Bewusst NICHT dieselbe Liste wie
    -- options.ignored. Dort steht "das will ich behalten, schlag es mir nicht
    -- zum Verkauf vor"; hier steht "damit will ich gar nicht handeln". Wer
    -- seine Manatraenke behaelt, meint damit nicht, dass ihn ein
    -- Manatrank-Flip nicht interessiert - zwei Aussagen, zwei Listen.
    db.options.rejected = db.options.rejected or {}
    db.questGold = db.questGold or {}
    db.roadmap = db.roadmap or {}
    db.roadmap.checked = db.roadmap.checked or {}
    db.roadmap.baseline = db.roadmap.baseline or {}
    db.goldHistory = db.goldHistory or {}
    -- 0.8.0: Sortierung der Chancenliste und des Handel-Tabs. Beides sind
    -- Ansichtseinstellungen, keine Filter - sie blenden nichts aus.
    if db.options.opportunitySort == nil then db.options.opportunitySort = "score" end
    if db.options.ledgerSort == nil then db.options.ledgerSort = "liquidity" end
    -- 0.9.0: Guide, Navigation und Zielmodus. Alle Voreinstellungen sind
    -- zurueckhaltend: Der Pfeil ist an, das automatische Einfuegen neuer
    -- Chancen in eine laufende Route ausdruecklich aus.
    if db.options.debug == nil then db.options.debug = false end
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
    -- Realmtrennung vor allem anderen: Alle Module holen ihren Speicher aus
    -- dem Profil, und das muss stehen, bevor eines davon anlaeuft.
    self.profileCache = nil
    self:MigrateProfiles()
    self:Profile()
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
    -- Farm Brain, Personal Brain und Kalibrierung legen sich leer an. Die
    -- Kalibrierung ist voreingestellt aus: Solange sie nichts gemessen hat,
    -- rechnet das Addon Punkt fuer Punkt wie das Standardmodell.
    if GCP.Farm then GCP.Farm:EnsureStore() end
    if GCP.Personal then
        GCP.Personal:EnsureStore()
        GCP.Personal:SyncOutcomes()
    end
    if GCP.Calibration then GCP.Calibration:EnsureStore() end
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
-- INCOME TRACKER (1.1.0). Alles, was einem Goldzufluss eine Ursache geben
-- kann. Jede Registrierung einzeln in pcall: Faehlt einer Clientfassung ein
-- Ereignisname, soll das Addon trotzdem laden.
for _, event in ipairs({
    "TRADE_SHOW", "TRADE_CLOSED", "TRADE_ACCEPT_UPDATE",
    "UI_INFO_MESSAGE", "CHAT_MSG_SYSTEM",
    "MERCHANT_SHOW", "MERCHANT_CLOSED",
    "QUEST_TURNED_IN", "QUEST_FINISHED",
    "CHAT_MSG_MONEY",
    "UNIT_SPELLCAST_SUCCEEDED",
    -- Gebuendelt nach Taschenaenderungen. Der einzige Weg, TATSAECHLICHEN
    -- Materialverbrauch zu messen statt theoretischen Rezeptbedarf.
    "BAG_UPDATE_DELAYED",
}) do
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        GCP:EnsureDB()
        GCP.initialized = true
    elseif event == "PLAYER_LOGIN" then
        if not GCP.db then GCP:EnsureDB() end
        GCP:RecordGold()
        -- Eine Sitzung, die noch offen im Speicher steht, wird bis zu ihrem
        -- letzten Lebenszeichen abgerechnet. Offline-Zeit faellt damit heraus,
        -- ohne dass sie jemand schaetzen muesste: Das Lebenszeichen hoert beim
        -- Ausloggen einfach auf.
        if GCP.Activity then pcall(GCP.Activity.RecoverSession, GCP.Activity) end
        GCP.Prices:RecordObservedPrices()
        GCP:Print("bereit. /gold öffnet deinen Gold-Berater.")
    elseif event == "PLAYER_MONEY" then
        if GCP.db then
            GCP:RecordGold()
            -- Der Income Tracker sieht denselben Zufluss - aber er fragt nach
            -- der URSACHE, und ohne Kontext heisst sie UNKNOWN.
            if GCP.Income then pcall(GCP.Income.OnMoney, GCP.Income) end
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        GCP:RecordPricesAfterAuction()
        GCP:NotifyMarketOfFreshPrices("Auktionshaus geschlossen")
    elseif GCP.Income then
        GCP:HandleIncomeEvent(event, arg1, arg2, arg3)
    end
end)

-- ---------------------------------------------------------------------------
-- INCOME-EREIGNISSE (1.1.0)
--
-- Der ganze Abschnitt existiert, weil der Client eine einzige Frage nicht
-- beantwortet: WARUM ist mein Gold mehr geworden? PLAYER_MONEY sagt nur, DASS
-- es mehr wurde. Alles hier setzt deshalb einen kurzen Kontext, in dem ein
-- Zufluss eine Ursache bekommt - und ohne Kontext bleibt er UNKNOWN.
--
-- Die drei Stellen, an denen der Client nicht mitspielt, und was daraus folgt:
--
--   1. TRADE_CLOSED feuert auch beim ABBRUCH. Es ist deshalb kein Beleg fuer
--      einen Handel, sondern nur das Ende des Fensters.
--   2. Nach dem Schliessen ist der Inhalt weg. Der Abzug muss beim
--      beidseitigen Bestaetigen entstehen - das ist der letzte Moment.
--   3. Der Abschluss wird ueber die Systemmeldung ERR_TRADE_COMPLETE belegt.
--      Sie ist lokalisiert; verglichen wird deshalb gegen die globale
--      Zeichenkette des Clients, nie gegen einen eigenen deutschen Text.
-- ---------------------------------------------------------------------------

function GCP:HandleIncomeEvent(event, arg1, arg2, arg3)
    local Income = self.Income
    if not Income then return end

    if event == "TRADE_SHOW" then
        Income:OnTradeClosed()          -- alter Rest raus, bevor es losgeht
    elseif event == "TRADE_ACCEPT_UPDATE" then
        -- Beide haben bestaetigt: JETZT den Abzug nehmen. Danach antwortet die
        -- Handels-API nicht mehr.
        if arg1 == 1 and arg2 == 1 then
            pcall(Income.OnTradeAccepted, Income)
        end
    elseif event == "TRADE_CLOSED" then
        -- Ausdruecklich KEIN Abschluss. Wer hier klassifiziert, zaehlt jeden
        -- abgebrochenen Handel mit.
        C_Timer.After(2, function()
            if Income.pendingTrade then Income:OnTradeClosed() end
        end)
    elseif event == "UI_INFO_MESSAGE" or event == "CHAT_MSG_SYSTEM" then
        local text = (event == "UI_INFO_MESSAGE") and arg2 or arg1
        if type(text) == "string" and type(ERR_TRADE_COMPLETE) == "string"
            and text == ERR_TRADE_COMPLETE then
            pcall(Income.OnTradeCompleted, Income)
        end
    elseif event == "MERCHANT_SHOW" then
        Income:SetContext("VENDOR")
    elseif event == "MERCHANT_CLOSED" then
        if Income.context and Income.context.source == "VENDOR" then
            Income:ClearContext()
        end
    elseif event == "QUEST_TURNED_IN" or event == "QUEST_FINISHED" then
        Income:SetContext("QUEST")
    elseif event == "CHAT_MSG_MONEY" then
        -- Beute ist der eine Fall, in dem der Client den Betrag im Klartext
        -- nennt. Der Kontext genuegt trotzdem: Die Summe holt sich der Tracker
        -- aus dem Goldstand, weil die Textzerlegung lokalisiert waere.
        Income:SetContext("LOOT")
    elseif event == "BAG_UPDATE_DELAYED" then
        if GCP.Materials then pcall(GCP.Materials.OnBagUpdate, GCP.Materials) end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Verzauberungen. Der Client nennt den Zauber, nicht den Kunden -
        -- deshalb ist das ein Kontext und nie ein Beleg.
        if arg1 == "player" and self.IsEnchantSpell and self:IsEnchantSpell(arg2, arg3) then
            Income:OnEnchantCast()
        end
    end
end

-- Ist dieser Zauber eine Verzauberung? Der Client liefert je nach Fassung
-- (unit, castGUID, spellID) oder (unit, spellName, ...); geprueft wird deshalb
-- beides, und im Zweifel gilt der Zauber NICHT als Verzauberung.
--
-- Die Zuordnung laeuft ueber den Namen der Berufsfertigkeit, nicht ueber eine
-- Liste von Zauber-IDs: Eine solche Liste waere in jedem Patch unvollstaendig,
-- und eine unvollstaendige Liste erzeugt genau die falsche Klassifikation, die
-- dieses Modul vermeiden soll.
function GCP:IsEnchantSpell(a, b)
    local spellID = tonumber(b) or tonumber(a)
    if not spellID or type(GetSpellInfo) ~= "function" then return false end
    local ok, name = pcall(GetSpellInfo, spellID)
    if not ok or type(name) ~= "string" then return false end
    for _, prefix in ipairs(self.Constants.ENCHANT_SPELL_PREFIXES) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

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
    self:Print(string.format("Orte: %d · Farmrouten: %d (nur belegte Koordinaten)",
        summary.locations, summary.farmRoutes))
    local problems = Knowledge:GetProblems()
    if #problems == 0 then
        self:Print("Prüfung der Wissensbasis: keine Widersprüche.")
    else
        self:Print(string.format("Prüfung der Wissensbasis: %d Problem(e)", #problems))
        for index, entry in ipairs(problems) do
            if index > 20 then
                self:Print(string.format("  ... und %d weitere", #problems - 20))
                break
            end
            self:Print(string.format("  %s %s – %s", entry.kind, entry.id, entry.problem))
        end
    end
end

-- ---------------------------------------------------------------------------
-- DIAGNOSE (0.9.0)
--
-- Eine kompakte Ausgabe, mit der sich ein Fehlerbericht schreiben laesst, ohne
-- dass jemand raten muss: Was ist geladen, wie viel liegt in den
-- SavedVariables, welche optionalen Addons sind da, und was macht die Route
-- gerade.
-- ---------------------------------------------------------------------------

function GCP:HasAddon(name)
    if name == "Auctionator" then
        return Auctionator ~= nil and Auctionator.API ~= nil
    elseif name == "Syndicator" then
        return GCP.Inventory:HasSyndicator()
    elseif name == "TSM" then
        return TSM_API ~= nil and type(TSM_API.GetCustomPriceValue) == "function"
    elseif name == "TomTom" then
        return GCP.Navigation and GCP.Navigation:HasTomTom() or false
    end
    return false
end

function GCP:BuildDiagnostics()
    local db = self.db or {}
    local market = GCP.Market:GetOverview()
    local ledger = GCP.Ledger:GetOverview()
    local knowledge = GCP.Knowledge:Summary()
    local capital = GCP.Capital:GetSnapshot()
    local guide = GCP.Guide:Progress()
    local lines = {}
    local function add(label, value)
        lines[#lines + 1] = { label = label, value = tostring(value) }
    end

    add("Version", GCP.Constants.VERSION)
    add("DB-Version", tostring(db.version))
    add("Wissensstand", GCP.Knowledge.VERSION_LABEL)
    add("Realm / Fraktion", GCP:ProfileKey())
    add("Profile", GCP:ProfileCount())
    add("Market Items", string.format("%d beobachtet, %d mit Historie",
        market.tracked, market.itemsWithHistory))
    add("Snapshots", string.format("%s über %d Tag(e)",
        GCP.Market:FormatCount(market.snapshots), market.spanDays or 0))
    add("Markttiefe", string.format("%d Item(s)", GCP.Market:DepthOverview().items))
    add("Ledger-Ereignisse", string.format("%s über %d Item(s)",
        GCP.Market:FormatCount(ledger.events), ledger.items))
    add("Offene Einstellungen", ledger.openPostings)
    add("Chancen", #((GCP.Opportunity:BuildReport() or {}).opportunities or {}))
    add("Chancen-Protokoll", #(GCP:Profile().opportunityHistory or {}))
    -- Die Beobachtungspunkte des Market Scores (1.0.0-beta.10). Sie stehen in
    -- der Diagnose, weil sie ein eigener Speicher sind - und weil ihre Zahl
    -- sagt, ab wann die Selbstpruefung ueberhaupt etwas hergibt.
    add("Score-Sonden", GCP.Market and #GCP.Market:GetProbes() or 0)
    add("Future-Wissen", string.format("%d Phasen, %d Catalysts, %d Kanten, %d Items",
        knowledge.phases, knowledge.catalysts, knowledge.edges, knowledge.items))
    add("Verworfenes Wissen", knowledge.rejected)
    add("Wissensprüfung", knowledge.problems == 0
        and "keine Widersprüche"
        or (knowledge.problems .. " Problem(e)"))
    add("Positionen", string.format("%d offen, %d ohne bekannten Einstand",
        capital.openPositions, capital.unknownCostPositions))
    add("Kapital", string.format("%s gesamt, %s frei, %s investiert",
        GCP.Prices:FormatGold(capital.currentGold),
        GCP.Prices:FormatGold(capital.availableGold),
        GCP.Prices:FormatGold(capital.investedCapital)))
    if guide and guide.steps > 0 then
        add("Route", string.format("%s · Schritt %d/%d · %d Neuplanung(en)",
            guide.stateLabel or guide.state, guide.step, guide.steps, guide.replans))
    else
        add("Route", "keine")
    end
    add("Gelernte Orte", GCP.Navigation:KnownCount())
    add("Farmsitzungen", GCP.Farm:SessionCount())
    add("Modell", GCP.Calibration:ModelLabel())
    add("Cache-Revisionen", string.format("Markt %d · Ledger %d · Kapital %d · Route %d · Guide %d",
        GCP.Market.revision or 0, GCP.Ledger.revision or 0,
        GCP.Capital.revision or 0, GCP.Route.revision or 0, GCP.Guide.revision or 0))
    add("Auctionator", self:HasAddon("Auctionator")
        and (market.callback and "erkannt (Callback aktiv)" or "erkannt (ohne Callback)")
        or "nicht erkannt")
    add("Syndicator", self:HasAddon("Syndicator") and "erkannt" or "nicht erkannt")
    add("TSM", self:HasAddon("TSM") and "erkannt" or "nicht erkannt")
    add("TomTom", self:HasAddon("TomTom") and "erkannt" or "nicht erkannt")
    add("Speicherbedarf", string.format("Markt ~%s · Handel ~%s",
        GCP.Market:FormatBytes(GCP.Market:EstimateBytes()),
        GCP.Market:FormatBytes(GCP.Ledger:EstimateBytes())))
    return lines
end

function GCP:PrintDiagnostics()
    self:Print("Diagnose:")
    for _, entry in ipairs(self:BuildDiagnostics()) do
        self:Print(string.format("  %s: %s", entry.label, entry.value))
    end
end

-- ---------------------------------------------------------------------------
-- Debug-Ausgaben. Nur mit eingeschaltetem Debugmodus - im Normalbetrieb soll
-- niemand versehentlich vierzig Zeilen im Chat haben.
-- ---------------------------------------------------------------------------

GCP.DEBUG_TOPICS = {
    market = "Markthistorie und Markttiefe",
    opportunity = "Chancen",
    future = "Zukunft",
    ledger = "Handelsbilanz",
    capital = "Kapital und Positionen",
    execution = "Aktionsgraph",
    route = "Route",
    guide = "Guide",
    farm = "Farmen",
    personal = "Persönliche Statistik",
}

local function debugMarket()
    local lines = {}
    local overview = GCP.Market:GetOverview()
    lines[#lines + 1] = string.format("Beobachtet: %d · Historie: %d Items · %s Punkte",
        overview.tracked, overview.itemsWithHistory,
        GCP.Market:FormatCount(overview.snapshots))
    local depth = GCP.Market:DepthOverview()
    lines[#lines + 1] = string.format("Markttiefe: %d Item(s), %d Stück insgesamt gesehen",
        depth.items, depth.quantity)
    for _, row in ipairs(GCP.Market:BuildReport(8) or {}) do
        lines[#lines + 1] = string.format("  %s: Score %s · %d Punkte",
            row.name or row.itemID, tostring(row.score), row.snapshots or 0)
    end
    return lines
end

local function debugOpportunity()
    local report = GCP.Opportunity:BuildReport()
    local lines = { GCP.Opportunity:SummaryText(report) }
    for index, opportunity in ipairs(report.opportunities or {}) do
        if index > 10 then break end
        lines[#lines + 1] = string.format("  [%d] %s %s · Kapital %s · Gewinn %s · %s",
            opportunity.opportunityScore, opportunity.type, opportunity.title or "?",
            GCP.Prices:FormatGold(opportunity.cost),
            GCP.Prices:FormatGold(opportunity.expectedProfit),
            opportunity.execution and "Bauplan vorhanden" or "OHNE BAUPLAN")
    end
    return lines
end

local function debugCapital()
    local snapshot = GCP.Capital:GetSnapshot(true)
    local lines = { GCP.Capital:SummaryText(snapshot) }
    lines[#lines + 1] = string.format("Exposure-Basis: %s",
        GCP.Prices:FormatGold(snapshot.exposureBase))
    for _, position in ipairs(snapshot.positions) do
        lines[#lines + 1] = string.format("  %s ×%d · Einstand %s · Wert %s · %s",
            position.name or position.itemID, position.quantity,
            position.costBasis and GCP.Prices:FormatMoney(position.costBasis) or "UNKNOWN",
            position.currentValue and GCP.Prices:FormatGold(position.currentValue) or "UNKNOWN",
            position.source)
    end
    for _, warning in ipairs(snapshot.warnings) do
        lines[#lines + 1] = "  ! " .. warning.text
    end
    return lines
end

local function debugRoute()
    local route = GCP.UI and GCP.UI.plannedRoute
    if not route then
        route = GCP.Route:Plan({ profile = "CUSTOM" })
    end
    local lines = { route.summary }
    for index, step in ipairs(route.steps) do
        lines[#lines + 1] = string.format("  %d. %s [%s] %s", index,
            step.title or step.type, step.type,
            step.location and step.location.kind or "-")
    end
    for _, warning in ipairs(route.warnings or {}) do
        lines[#lines + 1] = "  ! " .. warning
    end
    return lines
end

local function debugExecution()
    local route = GCP.UI and GCP.UI.plannedRoute or GCP.Route:Plan({ profile = "CUSTOM" })
    local plan = route.plan
    if not plan then return { "Kein Aktionsgraph." } end
    local lines = { string.format("%d Aktionen in %d Gruppe(n), gültig: %s",
        #plan.actions, #plan.groups, tostring(plan.valid)) }
    for _, action in ipairs(plan.actions) do
        lines[#lines + 1] = string.format("  %s %s ×%s <- %s", action.id, action.type,
            tostring(action.quantity), table.concat(action.dependencies, ",") )
    end
    for _, err in ipairs(plan.errors or {}) do lines[#lines + 1] = "  ! " .. err end
    return lines
end

local function debugGuide()
    local progress = GCP.Guide:Progress()
    if not progress or progress.steps == 0 then return { "Keine Route aktiv." } end
    local lines = {
        string.format("Zustand: %s · Schritt %d/%d · aktive Zeit %.1f Min · %d Neuplanung(en)",
            progress.state, progress.step, progress.steps,
            progress.activeMinutes, progress.replans),
    }
    local store = GCP:Profile().guide
    for index, step in ipairs(store.steps) do
        local mark = store.progress[step.id] and "x"
            or (store.skipped[step.id] and "-" or " ")
        lines[#lines + 1] = string.format("  [%s] %d. %s (%s)", mark, index,
            step.title or step.type, step.completionCondition or "?")
    end
    return lines
end

local function debugFuture()
    local report = GCP.Future:BuildReport()
    local lines = { GCP.Future:SummaryText(report) }
    for index, record in ipairs(report.items or {}) do
        if index > 10 then break end
        lines[#lines + 1] = string.format("  %s · Signal %s · Demand %s · Hype %s",
            record.name or record.itemID, tostring(record.futureOpportunityScore),
            tostring(record.futureDemandScore), tostring(record.hypeScore))
    end
    return lines
end

local function debugLedger()
    local overview = GCP.Ledger:GetOverview()
    local week = GCP.Ledger:GetGlobalStats(7)
    return {
        string.format("%s Ereignisse über %d Item(s), %d offene Einstellung(en)",
            GCP.Market:FormatCount(overview.events), overview.items,
            overview.openPostings),
        string.format("7 Tage: %s netto · %d Verkauf/Verkäufe · %d Ablauf/Abläufe",
            GCP.Prices:FormatGold(week.revenueNet), week.sales, week.expiries),
        "Einstell-Hook: " .. (overview.hooked and "aktiv" or "nicht eingehängt"),
    }
end

local function debugFarm()
    local lines = { GCP.Farm:SummaryText() }
    for _, zone in ipairs(GCP.Farm:Zones()) do
        local rate = GCP.Farm:GetRate(zone)
        if rate then
            lines[#lines + 1] = string.format("  %s: %s/h (Median, n=%d, %s)",
                zone, GCP.Prices:FormatGold(rate.medianGoldPerHour or 0),
                rate.sessions, rate.confidence)
        end
    end
    return lines
end

local function debugPersonal()
    local lines = { GCP.Personal:SummaryText() }
    for _, stats in ipairs(GCP.Personal:AllStats()) do
        lines[#lines + 1] = string.format("  %s: %d ausgeführt, %d übersprungen, "
            .. "%d Gewinn / %d Verlust", stats.type, stats.executed, stats.skipped,
            stats.wins, stats.losses)
    end
    for _, line in ipairs(GCP.Analytics:Lines()) do
        lines[#lines + 1] = "  " .. line
    end
    return lines
end

local DEBUG_HANDLERS = {
    market = debugMarket,
    opportunity = debugOpportunity,
    future = debugFuture,
    ledger = debugLedger,
    capital = debugCapital,
    execution = debugExecution,
    route = debugRoute,
    guide = debugGuide,
    farm = debugFarm,
    personal = debugPersonal,
}

function GCP:Debug(topic)
    if not (self.db and self.db.options.debug) then
        self:Print("Debug ist aus. Einschalten mit |cffd9a834/gold debug on|r.")
        return false
    end
    local handler = DEBUG_HANDLERS[topic]
    if not handler then
        local names = {}
        for key in pairs(self.DEBUG_TOPICS) do names[#names + 1] = key end
        table.sort(names)
        self:Print("Bereiche: " .. table.concat(names, ", "))
        return false
    end
    self:Print("Debug " .. topic .. ":")
    local ok, lines = pcall(handler)
    if not ok then
        self:Print("  Fehler: " .. tostring(lines))
        return false
    end
    for _, line in ipairs(lines) do self:Print("  " .. line) end
    return true
end

SLASH_GOLDCOPILOT1 = "/gold"
SLASH_GOLDCOPILOT2 = "/goldcopilot"
SlashCmdList["GOLDCOPILOT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if not GCP.db then GCP:EnsureDB() end
    -- 0.9.0: Befehle mit Argument zuerst, damit "/gold ziel 500" nicht als
    -- unbekannter Befehl im Fenster landet.
    local command, argument = msg:match("^(%S+)%s+(.+)$")
    if command == "debug" then
        if argument == "on" or argument == "an" then
            GCP.db.options.debug = true
            GCP:Print("Debug ist an.")
            return
        elseif argument == "off" or argument == "aus" then
            GCP.db.options.debug = false
            GCP:Print("Debug ist aus.")
            return
        end
        GCP:Debug(argument)
        return
    elseif command == "ziel" or command == "goal" then
        local amount = tonumber(argument)
        if amount and amount > 0 then
            GCP.db.options.goalAmount = math.floor(amount * 10000)
            GCP:Print("Goldziel: " .. GCP.Prices:FormatGold(GCP.db.options.goalAmount))
            if GCP.UI then GCP.UI:RefreshIfShown() end
        else
            GCP:Print("Beispiel: /gold ziel 500")
        end
        return
    elseif command == "zeit" or command == "time" then
        local minutes = tonumber(argument)
        if minutes and minutes > 0 then
            GCP.db.options.goalMinutes = math.floor(minutes)
            GCP:Print("Zeitbudget: " .. GCP.db.options.goalMinutes .. " Minuten")
            if GCP.UI then GCP.UI:RefreshIfShown() end
        else
            GCP:Print("Beispiel: /gold zeit 90")
        end
        return
    elseif command == "farm" then
        if argument == "start" then
            local session = GCP.Farm:Start(nil, nil)
            if session then
                GCP:Print("Farmsitzung in \"" .. tostring(session.zone)
                    .. "\" gestartet. Beenden mit |cffd9a834/gold farm stop|r.")
            else
                GCP:Print("Farmsitzung konnte nicht gestartet werden.")
            end
        elseif argument == "stop" or argument == "ende" then
            local status, _, stored = GCP.Farm:Stop("manuell")
            if not status then
                GCP:Print("Es läuft keine Farmsitzung.")
            elseif stored then
                GCP:Print(string.format("Farmsitzung beendet: %d Stück in %.0f Minuten "
                    .. "(%s geschätzter Wert).", status.totalItems, status.activeMinutes,
                    GCP.Prices:FormatGold(status.estimatedValue)))
            else
                GCP:Print("Farmsitzung beendet – zu kurz oder ohne Ausbeute, "
                    .. "deshalb nicht gewertet.")
            end
        else
            GCP:Print("Bekannt: /gold farm start · /gold farm stop")
        end
        if GCP.UI then GCP.UI:RefreshIfShown() end
        return
    elseif command == "route" then
        local profile = argument:upper():gsub("%s+", "_")
        if GCP.Route.PROFILE_SETUP[profile] then
            GCP.UI:PlanRouteFromGoal(profile)
            GCP.UI:Toggle()
            return
        end
        GCP:Print("Unbekanntes Profil. Bekannt: "
            .. table.concat(GCP.Constants.ROUTE.PROFILES, ", "))
        return
    end

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
    elseif msg == "diagnostics" or msg == "diagnose" then
        GCP:PrintDiagnostics()
    elseif msg == "debug" then
        GCP:Print("Debug ist " .. (GCP.db.options.debug and "an" or "aus")
            .. ". Umschalten: /gold debug on | off")
        GCP:Debug(nil)
    elseif msg == "route" then
        if GCP.UI then
            GCP.UI:PlanRouteFromGoal()
            GCP.UI:Toggle()
        end
    elseif msg == "start" then
        if GCP.UI then GCP.UI:StartRouteFromGoal() end
    elseif msg == "stop" or msg == "abbrechen" then
        if GCP.Personal then GCP.Personal:RecordRouteAborted() end
        GCP.Guide:Abort()
        GCP:Print("Route abgebrochen.")
        if GCP.UI then
            GCP.UI:RefreshGuide()
            GCP.UI:RefreshIfShown()
        end
    elseif msg == "pause" then
        if GCP.Guide:GetState() == "PAUSED" then
            GCP.Guide:Resume()
            GCP:Print("Route läuft weiter.")
        else
            GCP.Guide:Pause()
            GCP:Print("Route pausiert.")
        end
        if GCP.UI then GCP.UI:RefreshGuide() end
    elseif msg == "guide" then
        if GCP.UI then GCP.UI:ToggleGuideViewer() end
    elseif msg == "warum" or msg == "why" then
        if GCP.UI then GCP.UI:PrintGuideWhy() end
    elseif msg == "farm" then
        local running = GCP.Farm:Current()
        if running then
            local status = GCP.Farm:Status()
            GCP:Print(string.format("Farmsitzung läuft in \"%s\": %d Stück in "
                .. "%.0f Minuten.", tostring(status.zone), status.totalItems,
                status.activeMinutes))
            local assessment = GCP.Farm:Assess()
            if assessment and assessment.text then GCP:Print("  " .. assessment.text) end
            if assessment and assessment.alternative then
                GCP:Print("  " .. assessment.alternative.text)
            end
        end
        GCP:Print(GCP.Farm:SummaryText())
        for _, zone in ipairs(GCP.Farm:Zones()) do
            local rate = GCP.Farm:GetRate(zone)
            if rate and rate.medianGoldPerHour then
                GCP:Print(string.format("  %s: %s/h (Median aus %d Sitzung(en), %s)",
                    zone, GCP.Prices:FormatGold(rate.medianGoldPerHour),
                    rate.sessions, GCP.Market:ConfidenceLabel(rate.confidence)))
            end
        end
    elseif msg == "hilfe" or msg == "help" then
        GCP:Print("Befehle:")
        for _, line in ipairs({
            "/gold – Fenster öffnen",
            "/gold route [profil] – Route planen",
            "/gold start – Route starten",
            "/gold pause – Route anhalten oder fortsetzen",
            "/gold stop – Route abbrechen",
            "/gold guide – Guide-Fenster ein-/ausblenden",
            "/gold warum – Begründung des aktuellen Schritts",
            "/gold ziel 500 – Goldziel setzen (in Gold)",
            "/gold zeit 90 – Zeitbudget setzen (in Minuten)",
            "/gold diagnostics – kompakte Diagnose",
            "/gold debug on|off – Debugausgaben",
            "/gold farm start · /gold farm stop – Farmsitzung messen",
            "/gold chancen · zukunft · handel · farm · wissen · watchlist",
            "/gold marketstats · ledgerstats · marketreset · ledgerreset",
        }) do GCP:Print("  " .. line) end
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
