# ADHDBiS v1.5 Test Scenario

## Test 1: List View Layout (Gear tab)
- [ ] `/reload` pa `/adhd bis`
- [ ] Gear tab prikazuje nove redove umesto starih malih ikona
- [ ] Svaki red ima: veliku ikonu (42px) + ime itema u epic boji + "Drop: lokacija" ispod
- [ ] Prosiri prozor - pojavljuju se dve kolone (na sirini >=400px)
- [ ] Smanji prozor - vraca se na jednu kolonu
- [ ] Redovi imaju alternating background (svetliji/tamniji)

## Test 2: 4-State Status Icons
- [ ] Zelena kvacica = BiS item equipped na pravom ilvl-u (ikona dimmed/desaturated)
- [ ] Zuti sat = BiS equipped ali na nizem ilvl-u (upgradeable)
- [ ] Plava torba = BiS item u bagu ali nije equipped
- [ ] Crveni X = potpuno fali
- [ ] Equip BiS item - postane zeleno
- [ ] Stavi ga u bag - postane plavo

## Test 3: BiS Progress Footer
- [ ] Na dnu prozora pise nesto kao "8/16 equipped (50%)"
- [ ] Equip/unequip item - broj se azurira

## Test 4: Tooltip BiS Integration
- [ ] Otvori bag i hoveraj iteme - BiS itemi prikazuju "BiS: SpecName ClassName (Raid/M+)" u tooltipu
- [ ] Probaj na AH, trade window, loot - svuda gde hoveras item
- [ ] Hoveraj item koji NIJE BiS - ne sme da se pojavi BiS tekst

## Test 5: Raid/M+ Toggle
- [ ] Klikni Raid dugme - lista se menja
- [ ] Klikni M+ dugme - lista se menja
- [ ] Status ikone se azuriraju za svaki mode

## Test 6: Ostali tabovi (regression)
- [ ] Trinkets tab radi kao pre (grid sa tier sekcijama)
- [ ] Enchants+Gems tab radi kao pre
- [ ] Consumables tab radi kao pre
- [ ] Talents tab radi kao pre
- [ ] Vault tab radi kao pre

## Test 7: Click akcije na List View
- [ ] Left-click na item - otvara Adventure Guide popup
- [ ] Shift+Left-click - linkuje item u chat
- [ ] Right-click - toggle wishlist (zvezda se pojavi/nestane)
- [ ] Shift+Right-click - Wowhead URL copy box

## Test 8: Performance
- [ ] Otvori/zatvori BiS panel brzo vise puta - nema lag-a
- [ ] Menjaj klasu/spec u dropdown-u - instant
- [ ] FPS sa otvorenim panelom vs zatvoren - nema razlike

## Test 9: Dual Source (Icy Veins / Wowhead)
- [ ] Promeni source na Wowhead - lista se menja
- [ ] Vrati na Icy Veins - lista se vraca
- [ ] Tooltip BiS prikazuje iteme iz oba izvora
