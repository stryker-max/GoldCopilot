local addonName, GCP = ...

local Knowledge = GCP.Knowledge

-- ---------------------------------------------------------------------------
-- ITEMS DER WISSENSBASIS
--
-- Nur Items, ueber die 0.7 tatsaechlich etwas aussagt: Ziele von Catalysts,
-- Zutaten und Produkte des Dependency Graphs. Die Liste ist bewusst klein.
-- Vierzig belegte Zeilen sind mehr wert als fuenfhundert halbrichtige.
--
-- Jede Item-ID wurde gegen die TBC-Itemdatenbank (2.4.3-Spieldaten, wie sie
-- auch Questie ausliefert) geprueft - Name, ID und Itemklasse stimmen mit den
-- Spieldaten ueberein. Keine ID stammt aus dem Gedaechtnis.
--
-- Die englischen Namen dienen der Lesbarkeit und dem Abgleich mit den
-- Spieldaten; angezeigt wird zur Laufzeit immer der lokalisierte Name aus
-- GetItemInfo - genau wie in Constants.lua.
-- ---------------------------------------------------------------------------

local items = {
    -- Urelemente. Die fuenf Umwandlungsziele stehen bereits in Constants.lua;
    -- hier stehen sie, weil Phase 3 ihre Nachfrage veraendert.
    { id = 22456, name = "Primal Shadow", role = "material" },
    { id = 21886, name = "Primal Life", role = "material" },
    { id = 22451, name = "Primal Air", role = "material" },
    { id = 22457, name = "Primal Mana", role = "material" },
    { id = 21885, name = "Primal Water", role = "material" },

    -- Verzauberkunst-Rueckstaende
    { id = 22450, name = "Void Crystal", role = "material" },
    { id = 22449, name = "Large Prismatic Shard", role = "material" },
    { id = 22445, name = "Arcane Dust", role = "material" },

    -- Stoff
    { id = 21877, name = "Netherweave Cloth", role = "material" },
    { id = 21840, name = "Bolt of Netherweave", role = "material" },
    { id = 21842, name = "Bolt of Imbued Netherweave", role = "material" },
    { id = 21845, name = "Primal Mooncloth", role = "material" },
    { id = 24271, name = "Spellcloth", role = "material" },

    -- Leder und Schuppen
    { id = 21887, name = "Knothide Leather", role = "material" },
    { id = 23793, name = "Heavy Knothide Leather", role = "material" },
    { id = 25707, name = "Fel Hide", role = "material" },
    { id = 25700, name = "Fel Scales", role = "material" },

    -- Metall
    { id = 23425, name = "Adamantite Ore", role = "material" },
    { id = 23446, name = "Adamantite Bar", role = "material" },

    -- Das Leitmaterial der Phase 3: Trash-Drop im Schwarzen Tempel und am
    -- Berg Hyjal, Zutat praktisch jedes neuen Rezepts dieser Phase.
    { id = 32428, name = "Heart of Darkness", role = "material" },

    -- Kraeuter der Raid-Verbrauchsgueter
    { id = 22794, name = "Fel Lotus", role = "material" },
    { id = 22793, name = "Mana Thistle", role = "material" },
    { id = 22789, name = "Terocone", role = "material" },
    { id = 22792, name = "Nightmare Vine", role = "material" },

    -- Flakons
    { id = 22854, name = "Flask of Relentless Assault", role = "consumable" },
    { id = 22866, name = "Flask of Pure Death", role = "consumable" },

    -- Epische Sockelsteine (Phase 3)
    { id = 32227, name = "Crimson Spinel", role = "gem" },
    { id = 32228, name = "Empyrean Sapphire", role = "gem" },
    { id = 32229, name = "Lionseye", role = "gem" },
    { id = 32230, name = "Shadowsong Amethyst", role = "gem" },
    { id = 32231, name = "Pyrestone", role = "gem" },
    { id = 32249, name = "Seaspray Emerald", role = "gem" },

    -- Seltene Sockelsteine. Sie stehen hier, weil epische Steine sie im
    -- Endgame verdraengen - das ist die einzige Stelle der Wissensbasis, an der
    -- ein Catalyst nach unten zeigt.
    { id = 23436, name = "Living Ruby", role = "gem" },
    { id = 23437, name = "Talasite", role = "gem" },
    { id = 23438, name = "Star of Elune", role = "gem" },
    { id = 23439, name = "Noble Topaz", role = "gem" },
    { id = 23440, name = "Dawnstone", role = "gem" },
    { id = 23441, name = "Nightseye", role = "gem" },

    -- Hergestellte Ausruestung der Phase 3. Sie ist nicht der Markt, um den es
    -- geht - sie ist der Grund, warum sich der Markt der Zutaten bewegt.
    { id = 32391, name = "Soulguard Slippers", role = "crafted" },
    { id = 32404, name = "Shadesteel Greaves", role = "crafted" },
    { id = 32584, name = "Swiftheal Wraps", role = "crafted" },
    { id = 32580, name = "Swiftstrike Bracers", role = "crafted" },
    { id = 32586, name = "Bracers of Nimble Thought", role = "crafted" },
}

for _, entry in ipairs(items) do
    Knowledge:RegisterItem(entry)
end
