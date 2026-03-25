package scraper

import (
	"io"
	"time"
)

// ScrapeRequest defines what to scrape.
type ScrapeRequest struct {
	Classes    []ClassInfo
	ClassSpecs map[string][]ClassSpec // className -> specs to scrape
	Sources    []string              // "Icy Veins", "Wowhead", or both
}

// ScrapeResult holds all scraped data.
type ScrapeResult struct {
	// AllData: className -> specName -> sourceName -> SpecData
	AllData    map[string]map[string]map[string]*SpecData
	TotalItems int
}

// RunScrape performs the full scraping operation.
func RunScrape(req ScrapeRequest, logWriter io.Writer) *ScrapeResult {
	oldWriter := LogWriter
	LogWriter = logWriter
	defer func() { LogWriter = oldWriter }()

	result := &ScrapeResult{
		AllData: make(map[string]map[string]map[string]*SpecData),
	}

	for _, class := range req.Classes {
		specs := req.ClassSpecs[class.Name]
		if len(specs) == 0 {
			continue
		}

		if result.AllData[class.Name] == nil {
			result.AllData[class.Name] = make(map[string]map[string]*SpecData)
		}

		for _, spec := range specs {
			if result.AllData[class.Name][spec.Name] == nil {
				result.AllData[class.Name][spec.Name] = make(map[string]*SpecData)
			}

			for _, source := range req.Sources {
				logf("=== Scraping %s %s [%s] ===\n", class.Name, spec.Name, source)
				specData := &SpecData{
					Name:      spec.Name,
					ScrapedAt: time.Now().UTC().Format(time.RFC3339),
				}

				useWowhead := source == "Wowhead"
				var urls map[string]string
				if useWowhead {
					urls = WowheadURLs(class.Slug, spec)
				} else {
					urls = IcyVeinsURLs(class.Slug, spec)
				}

				// Gear
				logf("  Fetching BiS gear... (%s)\n", urls["gear"])
				gearResult, err := FetchPageWithMeta(urls["gear"])
				if err != nil {
					logf("  Warning: %v\n", err)
				}
				var gearBody []byte
				if gearResult != nil {
					gearBody = gearResult.Body
					if gearResult.LastModified != "" {
						specData.SourceLastModified = gearResult.LastModified
						logf("  Source Last-Modified: %s\n", gearResult.LastModified)
					}
				}
				if gearBody != nil {
					var raid, mythic, overall []GearItem
					var e error
					if useWowhead {
						raid, mythic, e = ParseWowheadGear(gearBody)
					} else {
						raid, mythic, overall, e = ParseGear(gearBody)
					}
					if e != nil {
						logf("  Parse warning: %v\n", e)
					} else {
						specData.OverallGear = overall
						specData.RaidGear = raid
						specData.MythicGear = mythic
						result.TotalItems += len(overall) + len(raid) + len(mythic)
					}
				}

				// Trinket Rankings (Icy Veins only - from same gear page)
				if !useWowhead && gearBody != nil {
					trinkets, te := ParseTrinketRankings(gearBody)
					if te != nil {
						logf("  Trinket ranking parse warning: %v\n", te)
					} else {
						specData.TrinketRankings = trinkets
						result.TotalItems += len(trinkets)
					}
				}

				Delay()

				// Enchants
				logf("  Fetching enchants & gems... (%s)\n", urls["enchants"])
				enchBody, err := FetchPage(urls["enchants"])
				if err != nil {
					logf("  Warning: %v\n", err)
				}
				if enchBody != nil {
					var ench []EnchantItem
					var gems []GemItem
					var cons []Consumable
					var e error
					if useWowhead {
						ench, gems, cons, e = ParseWowheadEnchants(enchBody)
					} else {
						ench, gems, cons, e = ParseEnchants(enchBody)
					}
					if e != nil {
						logf("  Parse warning: %v\n", e)
					} else {
						specData.Enchants = ench
						specData.Gems = gems
						specData.Consumables = cons
						result.TotalItems += len(ench) + len(gems) + len(cons)
					}
				}
				Delay()

				// Talents
				logf("  Fetching talents... (%s)\n", urls["talents"])
				talBody, err := FetchPage(urls["talents"])
				if err != nil {
					logf("  Warning: %v\n", err)
				}
				if talBody != nil {
					var talents []TalentBuild
					var e error
					if useWowhead {
						talents, e = ParseWowheadTalents(talBody)
					} else {
						talents, e = ParseTalents(talBody, class.Slug)
					}
					if e != nil {
						logf("  Parse warning: %v\n", e)
					} else {
						specData.TalentBuilds = talents
						result.TotalItems += len(talents)
					}
				}

				// Icy Veins talent codes are internal hashes, not WoW import strings.
				// Fallback: fetch talent codes from Wowhead which has real WoW import strings.
				if !useWowhead && len(specData.TalentBuilds) == 0 {
					logf("  No Icy Veins talent codes found, trying Wowhead fallback...\n")
					whURLs := WowheadURLs(class.Slug, spec)
					whBody, whErr := FetchPage(whURLs["talents"])
					if whErr == nil && whBody != nil {
						whTalents, whE := ParseWowheadTalents(whBody)
						if whE == nil && len(whTalents) > 0 {
							specData.TalentBuilds = whTalents
							result.TotalItems += len(whTalents)
							logf("    Got %d talent builds from Wowhead fallback\n", len(whTalents))
						}
					}
					Delay()
				}

				result.AllData[class.Name][spec.Name][source] = specData
				logf("\n")
				Delay()
			}
		}
	}

	return result
}
