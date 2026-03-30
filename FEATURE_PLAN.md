# ADHDBiS Feature Plan - v1.7 Release

## Overview

Cetiri feature-a koji ADHDBiS podizu na sledecu kategoriju gear management addona.
Sve je gear-focused i prirodno se uklapa u postojecu arhitekturu.

Redosled implementacije je odredjen po zavisnostima i impaktu.

---

## Feature 1: Tooltip BiS Integration

**Prioritet:** HIGHEST - najveci ROI, najlaksa implementacija
**Fajl:** `ADHDBiS.lua` (vec postoji HookTooltip na liniji ~2931)
**Kompleksnost:** Niska - hook vec radi, treba ga poboljsati

### Sta vec imamo
- `bisLookup[itemID]` tabela se gradi na PLAYER_ENTERING_WORLD
- `TooltipDataProcessor.AddTooltipPostCall()` vec hookovan
- Prikazuje BiS info za player class, Shift za ostale klase

### Sta treba dodati

#### 1A. BiS status u tooltip-u svuda (bag, AH, trade, loot, links)
- Vec radi za GameTooltip
- Dodati hook za `ItemRefTooltip` (chat linkovi) i `ShoppingTooltip` (AH compare)
- Testirati da radi u: bags, AH, trade window, loot frame, guild bank, mail, vendor

#### 1B. Vizualni indikator - BiS badge
- Dodati jednu liniju PRE item name-a: `[BiS] Raid` ili `[BiS] M+` ili `[BiS] Overall`
- Boja: zelena za tacno tvoj spec, zuta za tvoj class/drugi spec
- Format: `|cFF00FF00[BiS]|r Raid - Holy Paladin (Icy Veins)`
- Ako je item BiS za vise izvora: `[BiS] Raid + M+`

#### 1C. Upgrade indikator u tooltip-u
- Ako imas item equipped ali nizi ilvl: `|cFFFFFF00↑ Upgrade: your ilvl 619 → BiS ilvl 639|r`
- Ako nemas item uopste: `|cFFFF0000✗ Missing from your gear|r`
- Ako vec imas BiS ilvl: `|cFF00FF00✓ BiS equipped|r`

#### 1D. Gear source info
- Prikazati odakle item dolazi: `Source: The Voidspire - Lightblinded Vanguard`
- Ovo vec imamo u data fajlu, samo treba da se formatira za tooltip

### Estimacija: 1-2 sata rada

---

## Feature 2: 4-State Bag Scanner Window

**Prioritet:** HIGH - visual feedback za gear tracking
**Fajl:** Novi `ADHDBiS_BagScanner.lua` ili prosirenje Gear taba
**Kompleksnost:** Srednja - bag scanning vec postoji, treba UI

### Sta vec imamo
- `ScanBags()` funkcija (linija ~1005)
- `bagBiSCache[itemID]` sa inBag/bagIlvl
- `GetItemBiSState()` vraca 4 stanja
- Gear tab vec prikazuje 4-state ikonice (zelena/zuta/plava/crvena)

### Sta treba dodati

#### 2A. Filter na Gear tabu
- Dodati filter dugmice iznad liste: "All" | "Missing" | "In Bag" | "Upgradeable"
- "Missing" = crveni (nemam uopste)
- "In Bag" = plavi (imam ali nije equipped)
- "Upgradeable" = zuti (equipped ali nizi ilvl)
- Default: "All" (kako je sad)

#### 2B. Summary bar na vrhu Gear taba
- Horizontalan bar: `BiS Progress: 11/16 items (69%)`
- Vizualni progress bar (zeleni fill)
- Ispod: mini statistika po stanju:
  - `✓ 8 BiS equipped | ↑ 3 upgradeable | 📦 2 in bags | ✗ 3 missing`
- Boje matcuju 4-state sistem

#### 2C. Quick Actions
- Klik na "In Bag" item → highlight u bagu (opcionalno, moze biti kompleksno)
- Shift+click na "Missing" item → link u chat
- Right-click → "Where does this drop?" otvara Adventure Guide

### Odluka: Da li pravimo zaseban prozor ili prosirujemo Gear tab?
**Preporuka: Prosiriti Gear tab** - manje koda, korisnik vec zna gde da nadje gear info.
Dodati filter + summary bar iznad postojeceg lista.

### Estimacija: 2-3 sata rada

---

## Feature 3: Great Vault Enhancement

**Prioritet:** HIGH - vec imamo osnovu, treba je unaprediti
**Fajl:** `ADHDBiS.lua` (RenderVault, linija ~1986)
**Kompleksnost:** Srednja - API postoji, UI treba preraditi

### Sta vec imamo
- Vault tab sa 3 sekcije (Raid/M+/Delves)
- Text-based progress bar
- ilvl prikaz iz C_WeeklyRewards API
- Status: UNLOCKED vs X/Y progress

### Sta treba dodati

#### 3A. Vizualni progress barovi (umesto text-based)
- Pravi StatusBar frame umesto ASCII bar-a
- Zeleni fill za progress, zlatan border kad unlocked
- Velicina: bar sirina prilagodjena prozoru

#### 3B. BiS overlay na Vault rewards
- Kad je slot UNLOCKED, proveri da li reward ilvl odgovara BiS listi
- Oznaci: `★ Contains potential BiS upgrade` ili `No BiS items at this ilvl`
- Ovo zahteva cross-referencing vault ilvl sa BiS item ilvl-ovima iz data fajla

#### 3C. Weekly progress summary
- Na vrhu Vault taba: `This Week: 3/9 slots unlocked`
- Mini progress ring ili bar za ukupan vault status
- "Best reward: ilvl 639 from Mythic+" highlight

#### 3D. Vault BiS Recommendation
- Kad vault moze da se otvori (`CanClaimRewards()`):
  - Lista svih mogucih rewarda sa ilvl-om
  - Oznaci koji su BiS za tvoj spec
  - Preporuka: "Pick Slot 2 (Mythic+) - contains BiS trinket at ilvl 639"
- Ovo je killer feature - niko drugi ovo ne radi

#### 3E. Reset countdown
- "Vault resets in: 2d 14h 32m"
- Izracunati na osnovu regiona (US=Tuesday, EU=Wednesday)
- `C_DateAndTime.GetSecondsUntilWeeklyReset()` API

### Estimacija: 3-4 sata rada

---

## Feature 4: Enhanced List View

**Prioritet:** MEDIUM - QoL improvement
**Fajl:** `ADHDBiS.lua` (RenderGear, vec postoji)
**Kompleksnost:** Niska-Srednja

### Sta vec imamo
- 2-column list view sa ikonom, imenom, izvorom
- 4-state status (zelena/zuta/plava/crvena border)
- Wishlist star toggle
- Sort po slotu

### Sta treba dodati

#### 4A. Sort opcije
- Dugme za sort: "By Slot" (default) | "By Status" | "By Source"
- "By Status" stavlja missing/upgradeable na vrh - najkorisnije
- "By Source" grupise po dungeon/raid boss-u

#### 4B. Kompaktni ilvl prikaz
- Dodati ilvl tekst na svaki red: `ilvl 639` pored imena
- Ako equipped: `619 → 639` sa strelicom u boji
- Kompaktno, ne zauzima puno prostora

#### 4C. Drop location ikonica
- Mali icon pored source texta:
  - Skull icon = raid boss
  - Key icon = M+ dungeon
  - Hammer icon = crafted
  - Star icon = world drop / catalyst

#### 4D. Slot grouping headers
- Opcioni section headers: "-- Head, Neck, Shoulder --" itd.
- Ili grouping po armor type: "Weapons", "Armor", "Jewelry"
- Toggle u settings

### Estimacija: 2-3 sata rada

---

## Implementacioni Redosled

```
Phase 1 (Brzo, veliki impact):
  └─ Feature 1: Tooltip BiS Integration (1-2h)
       Razlog: Najmanje koda, najveci user-facing impact
       Svi igraci vide tooltip-e non-stop

Phase 2 (Core upgrade):
  ├─ Feature 2: Bag Scanner Filter + Progress Bar (2-3h)
  │    Razlog: Gear tab postaje pravi gear management tool
  └─ Feature 3: Great Vault Enhancement (3-4h)
       Razlog: BiS recommendation je unique selling point

Phase 3 (Polish):
  └─ Feature 4: Enhanced List View (2-3h)
       Razlog: QoL, moze i posle release-a
```

**Ukupno: ~8-12 sati rada za sve**

---

## Tehnicke Napomene

### Fajl struktura posle implementacije
```
addon/ADHDBiS/
  ADHDBiS.toc          -- dodati novi fajl ako pravimo BagScanner
  ADHDBiS_Data.lua     -- nepromenjeno
  ADHDBiS.lua          -- Features 1, 3, 4 (tooltip, vault, list view)
  ADHDBiS_Overview.lua -- nepromenjeno
  ADHDBiS_LootTracker.lua -- nepromenjeno
  ADHDBiS_LootRadar.lua   -- nepromenjeno
```

### Performanse
- Tooltip hook: O(1) lookup u bisLookup tabeli - BRZO
- Bag filter: Koristi vec existing bagBiSCache - BRZO
- Vault enhancement: C_WeeklyRewards API je brz, jedan poziv po renderovanju
- Sort: table.sort na max 16 itema - zanemarljivo

### API-ji koji su nam potrebni (vec dostupni)
- `TooltipDataProcessor` - vec koristimo
- `C_WeeklyRewards.GetActivities()` - vec koristimo
- `C_WeeklyRewards.CanClaimRewards()` - vec koristimo
- `C_WeeklyRewards.GetExampleRewardItemHyperlinks()` - vec koristimo
- `C_DateAndTime.GetSecondsUntilWeeklyReset()` - novo, ali standardan API
- `C_Container.GetContainerItemInfo()` - vec koristimo u ScanBags

### Novi API-ji (proveriti dostupnost u 12.0)
- `C_WeeklyRewards.GetExampleRewardItemHyperlinks()` - moze biti promenjeno u Midnight
- StatusBar frames - standardni WoW widget, uvek dostupan

---

## Versioning Plan

- Feature 1 (Tooltip) → v1.6.3
- Features 2+3 (Bag Scanner + Vault) → v1.7.0 (major feature release)
- Feature 4 (List View) → v1.7.1

Ili sve odjednom kao v1.7.0 "Gear Intelligence Update"
