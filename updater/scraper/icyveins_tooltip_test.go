package scraper

import (
	"os"
	"testing"
)

// Icy Veins replaced data-wowhead="item=ID&bonus=X" with
// data-iv-tooltip="wow/item/ID?bonus=X" (seen 2026-11-08). These fixtures are real
// pages saved on that date; the parsers returned 0 items on them. They are third-party
// pages, so they are not committed (testdata/ is gitignored) and the tests skip without them.

func readFixture(t *testing.T, path string) []byte {
	t.Helper()
	body, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		t.Skipf("fixture %s not present", path)
	}
	if err != nil {
		t.Fatal(err)
	}
	return body
}

func TestParseGearIcyVeinsTooltipMarkup(t *testing.T) {
	body := readFixture(t, "testdata/iv_frost_dk_gear.html")
	raid, mythic, overall, err := ParseGear(body)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("overall=%d raid=%d mythic=%d", len(overall), len(raid), len(mythic))
	if len(overall) < 14 {
		t.Fatalf("expected a full overall BiS list, got %d items", len(overall))
	}
	var helm *GearItem
	for i := range overall {
		if overall[i].Slot == "Head" {
			helm = &overall[i]
		}
	}
	if helm == nil {
		t.Fatalf("no Head slot in overall list: %+v", overall)
	}
	if helm.ItemID != 281239 || helm.BonusIDs != "12854:14049" || helm.Name != "Corroded Hulk's Skullcap" || helm.Source != "Kith'ix" {
		t.Fatalf("wrong helm: %+v", *helm)
	}
}

func TestParseEnchantsIcyVeinsTooltipMarkup(t *testing.T) {
	body := readFixture(t, "testdata/iv_frost_dk_enchants.html")
	enchants, gems, consumables, err := ParseEnchants(body)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("enchants=%d gems=%d consumables=%d", len(enchants), len(gems), len(consumables))
	if len(enchants) == 0 || len(gems) == 0 || len(consumables) == 0 {
		t.Fatalf("expected enchants, gems and consumables, got %d/%d/%d", len(enchants), len(gems), len(consumables))
	}
}
