package scraper

import (
	"bytes"
	"fmt"
	"regexp"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// Regex to extract talent build hashes from MidnightTalentCalculator init scripts.
// Pattern: "midnight-skill-builder-N", "#HASH_STRING"
// Icy Veins uses ":" instead of "/" in their base64 hash table, so include ":" in pattern.
// Some hashes end with "*" (e.g. Windwalker Monk), so include "*" in pattern.
var talentHashRegex = regexp.MustCompile(`"(midnight-skill-builder-\d+)"[^"]*"(#[A-Za-z0-9+/:=_*-]+)"`)

// isValidWoWTalentCode checks if a string looks like a valid WoW talent import code.
// Valid codes start with "C" and are 50+ characters of base64.
func isValidWoWTalentCode(code string) bool {
	return len(code) >= 50 && strings.HasPrefix(code, "C")
}

// ParseTalents parses talent builds from an Icy Veins talents page.
// Talent builds on Icy Veins are in image_block tabs with area_N_button labels.
// The actual build hashes are in <script> tags that init MidnightTalentCalculator.
func ParseTalents(body []byte, classSlug string) (builds []TalentBuild, err error) {
	doc, err := goquery.NewDocumentFromReader(bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("parsing HTML: %w", err)
	}

	bodyStr := string(body)

	// Step 1: Collect tab button labels (build names) mapped to builder IDs
	// Tab buttons: <span id="area_N_button">Build Name</span>
	// Builder containers: <div id="midnight-skill-builder-N"> inside area_N
	tabNames := map[int]string{}     // area index -> name
	tabContexts := map[int]string{}  // area index -> context guess

	doc.Find(".image_block_header_buttons span").Each(func(i int, s *goquery.Selection) {
		id, exists := s.Attr("id")
		if !exists {
			return
		}
		// Extract area number from "area_N_button"
		if !strings.HasPrefix(id, "area_") || !strings.HasSuffix(id, "_button") {
			return
		}
		numStr := strings.TrimSuffix(strings.TrimPrefix(id, "area_"), "_button")
		var num int
		fmt.Sscanf(numStr, "%d", &num)
		if num == 0 {
			return
		}

		name := strings.TrimSpace(s.Text())
		tabNames[num] = name

		// Guess context from name
		nameLower := strings.ToLower(name)
		if strings.Contains(nameLower, "single") || strings.Contains(nameLower, "raid") || strings.Contains(nameLower, "boss") || strings.Contains(nameLower, "st ") {
			tabContexts[num] = "raid"
		} else if strings.Contains(nameLower, "aoe") || strings.Contains(nameLower, "mythic") || strings.Contains(nameLower, "m+") || strings.Contains(nameLower, "dungeon") {
			tabContexts[num] = "mythicplus"
		} else if strings.Contains(nameLower, "delve") {
			tabContexts[num] = "delves"
		} else if strings.Contains(nameLower, "pvp") {
			tabContexts[num] = "pvp"
		} else {
			tabContexts[num] = "general"
		}
	})

	// Step 2: Extract talent hashes from script tags
	// Pattern: new MidnightTalentCalculator("midnight-skill-builder-N", "#HASH", ...)
	builderHashes := map[string]string{} // "midnight-skill-builder-N" -> hash
	matches := talentHashRegex.FindAllStringSubmatch(bodyStr, -1)
	for _, m := range matches {
		if len(m) >= 3 {
			builderHashes[m[1]] = m[2]
		}
	}

	// Step 3: Map builder IDs to areas
	// Each area_N contains a midnight-skill-builder-N div
	builderToArea := map[string]int{}
	for areaNum := range tabNames {
		areaID := fmt.Sprintf("area_%d", areaNum)
		doc.Find(fmt.Sprintf("#%s .midnight-skill-builder-embed", areaID)).Each(func(i int, div *goquery.Selection) {
			divID, exists := div.Attr("id")
			if exists {
				builderToArea[divID] = areaNum
			}
		})
	}

	// Step 4: Build talent entries
	for builderID, hash := range builderHashes {
		areaNum, mapped := builderToArea[builderID]
		name := "Unknown Build"
		context := "general"

		if mapped {
			if n, ok := tabNames[areaNum]; ok {
				name = n
			}
			if c, ok := tabContexts[areaNum]; ok {
				context = c
			}
		} else {
			// Try to infer from builder ID number
			var builderNum int
			fmt.Sscanf(builderID, "midnight-skill-builder-%d", &builderNum)
			if n, ok := tabNames[builderNum]; ok {
				name = n
			}
			if c, ok := tabContexts[builderNum]; ok {
				context = c
			}
		}

		// Convert Icy Veins internal hash to WoW talent import string
		code, convErr := ConvertIcyVeinsHash(hash, classSlug)
		if convErr != nil {
			logf("    Failed to convert talent code for %s: %v\n", name, convErr)
			continue
		}
		if !isValidWoWTalentCode(code) {
			logf("    Skipping invalid talent code for %s (converted: %s...)\n", name, code[:min(20, len(code))])
			continue
		}

		builds = append(builds, TalentBuild{
			Name:    name,
			Code:    code,
			Context: context,
		})
	}

	// Fallback: also try a broader regex for talent strings in any script tag
	if len(builds) == 0 {
		altRegex := regexp.MustCompile(`"(#[A-Za-z0-9+/:=_*-]{30,})"`)
		altMatches := altRegex.FindAllStringSubmatch(bodyStr, -1)
		for i, m := range altMatches {
			if len(m) >= 2 {
				code, convErr := ConvertIcyVeinsHash(m[1], classSlug)
				if convErr != nil || !isValidWoWTalentCode(code) {
					continue
				}
				name := fmt.Sprintf("Build %d", i+1)
				context := "general"
				if i == 0 {
					context = "raid"
				} else {
					context = "mythicplus"
				}
				builds = append(builds, TalentBuild{Name: name, Code: code, Context: context})
			}
		}
	}

	logf("    Found %d talent builds\n", len(builds))
	return builds, nil
}
