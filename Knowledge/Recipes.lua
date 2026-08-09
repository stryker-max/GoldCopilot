local addonName, GCP = ...

local Knowledge = GCP.Knowledge

-- ---------------------------------------------------------------------------
-- DEPENDENCY GRAPH: MATERIALABHAENGIGKEITEN
--
-- Kanten von Material (from) zu Produkt (to). Darueber wandert die Nachfrage
-- eines neuen Rezepts zu seinen Zutaten - und von dort eine Ebene weiter zu
-- deren Zutaten.
--
-- Was hier NICHT steht, ist ein Rezeptbuch. Gold Copilot kennt die Rezepte des
-- Spielers bereits: Crafts.lua liest sie beim Oeffnen des Berufsfensters direkt
-- aus dem Client, und Constants.CRAFT_COOLDOWNS haelt die Umwandlungen. Beides
-- baut Future.lua zusaetzlich in den Graphen ein. Hier stehen nur die wenigen
-- Verbindungen, die fuer die kommende Phase zaehlen und die auch jemand sieht,
-- der den entsprechenden Beruf gar nicht hat.
--
-- MENGENANGABEN: quantity steht nur da, wo die Menge belegt ist. Wo nur die
-- Beziehung gesichert ist (Barren werden aus Erz geschmolzen), bleibt quantity
-- nil und die Erklaerung sagt "Menge nicht hinterlegt". Eine erfundene Zahl
-- waere schlimmer als eine fehlende - fuer die Rechnung ist sie ohnehin
-- unerheblich, sie zaehlt nur fuer die Anzeige.
--
-- Quelle aller Rezeptzeilen: TBC-Spieldaten 2.4.3, gegengeprueft mit den
-- Item-IDs aus Knowledge/Items.lua.
-- ---------------------------------------------------------------------------

local GAME_DATA = "TBC-Spieldaten 2.4.3 (Rezeptdaten)"

local function craft(product, recipeName, spell, mats, note)
    for _, mat in ipairs(mats) do
        Knowledge:RegisterEdge({
            from = mat[1],
            to = product,
            quantity = mat[2],
            relation = "craft_material",
            recipe = recipeName,
            spell = spell,
            sourceConfidence = "historical",
            sourceName = GAME_DATA,
            sourceNote = note,
        })
    end
end

-- --- Schattenwiderstand fuer Mutter Shahraz (Phase 3) -----------------------
-- Stellvertretend fuer je eine Ruestungsklasse: Stoff und Platte. Die vier
-- Sets (Soulguard, Shadesteel, Redeemed Soul, Shackled Souls) folgen demselben
-- Muster - Urschatten, Urleben, ein Nichtsplitter, das ruestungstypische
-- Grundmaterial und Herz der Finsternis.
craft(32391, "Soulguard Slippers", 40020, {
    { 21842, 1 },   -- Bolt of Imbued Netherweave
    { 21886, 2 },   -- Primal Life
    { 22450, 1 },   -- Void Crystal
    { 22456, 4 },   -- Primal Shadow
    { 32428, 2 },   -- Heart of Darkness
})

craft(32404, "Shadesteel Greaves", 40035, {
    { 21886, 4 },   -- Primal Life
    { 22450, 1 },   -- Void Crystal
    { 22456, 6 },   -- Primal Shadow
    { 23446, 12 },  -- Adamantite Bar
    { 32428, 3 },   -- Heart of Darkness
})

-- --- Hergestellte Spitzenausruestung der Phase 3 ----------------------------
craft(32584, "Swiftheal Wraps", 41207, {
    { 21842, 3 },   -- Bolt of Imbued Netherweave
    { 21845, 4 },   -- Primal Mooncloth
    { 21886, 8 },   -- Primal Life
    { 32428, 4 },   -- Heart of Darkness
})

craft(32586, "Bracers of Nimble Thought", 41205, {
    { 21842, 3 },   -- Bolt of Imbued Netherweave
    { 22457, 8 },   -- Primal Mana
    { 24271, 4 },   -- Spellcloth
    { 32428, 4 },   -- Heart of Darkness
})

craft(32580, "Swiftstrike Bracers", 41158, {
    { 23793, 4 },   -- Heavy Knothide Leather
    { 22451, 10 },  -- Primal Air
    { 32428, 4 },   -- Heart of Darkness
})

-- --- Zwischenstufen ---------------------------------------------------------
-- Erst diese Kanten machen aus dem Graphen mehr als eine Stueckliste: Die
-- Nachfrage nach Seelenwaechterschuhen erreicht ueber zwei Ebenen den
-- Netherstoff, aus dem alles gewebt wird.
-- Ohne Zauber-ID, wo sie nicht belegt ist: Der Rezeptname ist gesichert, die
-- Nummer waere geraten.
craft(21845, "Primal Mooncloth", nil, {
    { 21842, 1 },   -- Bolt of Imbued Netherweave
    { 21886, 1 },   -- Primal Life
    { 21885, 1 },   -- Primal Water
})

craft(21842, "Bolt of Imbued Netherweave", nil, {
    { 21840, 3 },   -- Bolt of Netherweave
    { 22445, 2 },   -- Arcane Dust
})

craft(21840, "Bolt of Netherweave", 26745, {
    { 21877 },      -- Netherweave Cloth, Menge nicht hinterlegt
}, "Menge nicht hinterlegt")

craft(23793, "Heavy Knothide Leather", nil, {
    { 21887 },      -- Knothide Leather, Menge nicht hinterlegt
}, "Menge nicht hinterlegt")

Knowledge:RegisterEdge({
    from = 23425, to = 23446,       -- Adamantite Ore -> Adamantite Bar
    relation = "smelt_material",
    recipe = "Smelt Adamantite",
    spell = 29358,
    sourceConfidence = "historical",
    sourceName = GAME_DATA,
    sourceNote = "Menge nicht hinterlegt",
})

-- --- Raid-Verbrauchsgueter --------------------------------------------------
-- Die beiden Flakons stehen stellvertretend fuer den Verbrauch eines
-- Raidabends. Der Imbued Vial ist Haendlerware und deshalb keine Kante: Er hat
-- keinen Markt, der sich bewegen koennte.
craft(22854, "Flask of Relentless Assault", 28589, {
    { 22794, 1 },   -- Fel Lotus
    { 22793, 3 },   -- Mana Thistle
    { 22789, 7 },   -- Terocone
})

craft(22866, "Flask of Pure Death", nil, {
    { 22794, 1 },   -- Fel Lotus
    { 22793, 3 },   -- Mana Thistle
    { 22792, 7 },   -- Nightmare Vine
})
