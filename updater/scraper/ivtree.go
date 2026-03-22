package scraper

import (
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"
)

// Base64 tables matching Icy Veins' MidnightTalentCalculator JS.
var (
	// Standard base64 for WoW export strings.
	base64Table = []byte("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
	// Icy Veins internal hash uses ":" instead of "/".
	hashBase64Table = []byte("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+:")
)

// bitReader reads bits from a base64-encoded string (LSB first, 6 bits per char).
type bitReader struct {
	bits []int
	pos  int
}

func newBitReader(s string, table []byte) *bitReader {
	lookup := make(map[byte]int, len(table))
	for i, ch := range table {
		lookup[ch] = i
	}
	var bits []int
	for i := 0; i < len(s); i++ {
		val, ok := lookup[s[i]]
		if !ok {
			continue
		}
		for j := 0; j < 6; j++ {
			bits = append(bits, (val>>j)&1)
		}
	}
	return &bitReader{bits: bits}
}

func (r *bitReader) read(width int) int {
	if r.pos+width > len(r.bits) {
		return -1
	}
	result := 0
	for i := 0; i < width; i++ {
		result += r.bits[r.pos+i] << i
	}
	r.pos += width
	return result
}

func (r *bitReader) hasMore() bool {
	return r.pos < len(r.bits)
}

// bitWriter writes bits to a base64-encoded string (LSB first, 6 bits per char).
type bitWriter struct {
	bits  []int
	table []byte
}

func newBitWriter(table []byte) *bitWriter {
	return &bitWriter{table: table}
}

func (w *bitWriter) write(value, width int) {
	for i := 0; i < width; i++ {
		w.bits = append(w.bits, (value>>i)&1)
	}
}

func (w *bitWriter) toExportString() string {
	// Pad to multiple of 6
	for len(w.bits)%6 != 0 {
		w.bits = append(w.bits, 0)
	}
	var sb strings.Builder
	for i := 0; i < len(w.bits); i += 6 {
		val := w.bits[i]*1 + w.bits[i+1]*2 + w.bits[i+2]*4 +
			w.bits[i+3]*8 + w.bits[i+4]*16 + w.bits[i+5]*32
		sb.WriteByte(w.table[val])
	}
	return sb.String()
}

// Icy Veins tree JSON structures.
type ivTreeJSON struct {
	UnusedNodeIDs []int                  `json:"unusedNodeIds"`
	Specs         map[string]ivSpecJSON  `json:"specs"`
}

type ivSpecJSON struct {
	ID         int                     `json:"id"`
	ClassNodes map[string]ivNodeJSON   `json:"classNodes"`
	SpecNodes  map[string]ivNodeJSON   `json:"specNodes"`
	Hero       ivHeroJSON              `json:"hero"`
	ApexNode   ivApexNodeJSON          `json:"apexNode"`
}

type ivNodeJSON struct {
	ID              int           `json:"id"`
	Type            string        `json:"type"` // "round", "square", "choice"
	Spells          []ivSpellJSON `json:"spells"`
	AlreadyMaxedOut bool          `json:"alreadyMaxedOut"`
}

type ivSpellJSON struct {
	MaxRanks int `json:"maxRanks"`
}

type ivHeroJSON struct {
	MetaNodeID int        `json:"metaNodeId"`
	Left       ivHeroSide `json:"left"`
	Right      ivHeroSide `json:"right"`
}

type ivHeroSide struct {
	Name       string                 `json:"name"`
	RootNodeID int                    `json:"rootNodeId"`
	Nodes      map[string]ivNodeJSON  `json:"nodes"`
}

type ivApexNodeJSON struct {
	ID     int           `json:"id"`
	Spells []ivSpellJSON `json:"spells"`
}

// Cache for tree JSON data.
var (
	treeCache   = map[string]*ivTreeJSON{}
	treeCacheMu sync.Mutex
)

const ivTreeJSONBase = "https://static.icy-veins.com/json/midnight-talent-calculator"
const ivTreeJSONVersion = "44"

func fetchTreeJSON(classSlug string) (*ivTreeJSON, error) {
	// Convert scraper slug (death-knight) to IV JSON name (death_knight)
	jsonName := strings.ReplaceAll(classSlug, "-", "_")

	treeCacheMu.Lock()
	if cached, ok := treeCache[jsonName]; ok {
		treeCacheMu.Unlock()
		return cached, nil
	}
	treeCacheMu.Unlock()

	url := fmt.Sprintf("%s/%s.json?v=%s", ivTreeJSONBase, jsonName, ivTreeJSONVersion)
	client := &http.Client{Timeout: 15 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return nil, fmt.Errorf("fetching tree JSON: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("tree JSON HTTP %d", resp.StatusCode)
	}

	var tree ivTreeJSON
	if err := json.NewDecoder(resp.Body).Decode(&tree); err != nil {
		return nil, fmt.Errorf("decoding tree JSON: %w", err)
	}

	treeCacheMu.Lock()
	treeCache[jsonName] = &tree
	treeCacheMu.Unlock()
	return &tree, nil
}

// nodeState tracks the state of a talent node after replaying actions.
type nodeState struct {
	points   int
	choice   int  // which choice was picked (0 or 1)
	isChoice bool // whether this is a choice node
}

// replayActions decodes an Icy Veins hash section and returns the state of each node.
func replayActions(hashSection string, nodeIDs []int, nodeTypes map[int]string, nodeMaxRanks map[int]int) map[int]*nodeState {
	states := make(map[int]*nodeState)
	if hashSection == "" {
		return states
	}
	reader := newBitReader(hashSection, hashBase64Table)
	for reader.hasMore() {
		nodeIndex := reader.read(6)
		if nodeIndex < 0 || nodeIndex >= len(nodeIDs) {
			break
		}
		nodeID := nodeIDs[nodeIndex]
		isChoice := nodeTypes[nodeID] == "choice"

		st, exists := states[nodeID]
		if !exists {
			st = &nodeState{isChoice: isChoice}
			states[nodeID] = st
		}

		if isChoice {
			ch := reader.read(1)
			if ch < 0 {
				break
			}
			st.choice = ch
			st.points = 1
		} else {
			st.points++
		}
	}
	return states
}

// sortedNodeIDs extracts integer node IDs from a map and returns them sorted.
func sortedNodeIDs(nodes map[string]ivNodeJSON) []int {
	ids := make([]int, 0, len(nodes))
	for _, n := range nodes {
		ids = append(ids, n.ID)
	}
	sort.Ints(ids)
	return ids
}

// ConvertIcyVeinsHash converts an Icy Veins internal talent hash to a WoW talent import string.
func ConvertIcyVeinsHash(hash string, classSlug string) (string, error) {
	tree, err := fetchTreeJSON(classSlug)
	if err != nil {
		return "", err
	}

	// Parse hash sections: specId-class-spec-[apex]-hero-pvp
	h := strings.TrimPrefix(hash, "#")
	// Strip trailing "*" (some specs like Windwalker Monk have it)
	h = strings.TrimRight(h, "*")
	parts := strings.Split(h, "-")
	if len(parts) < 4 {
		return "", fmt.Errorf("invalid hash: too few sections (%d)", len(parts))
	}

	hasApex := len(parts) >= 6
	specIDStr := parts[0]
	classStr := parts[1]
	specStr := parts[2]
	var apexStr, heroStr string
	if hasApex {
		apexStr = parts[3]
		heroStr = parts[4]
	} else {
		heroStr = parts[3]
	}

	// Decode spec ID (12 bits)
	specReader := newBitReader(specIDStr, hashBase64Table)
	specID := specReader.read(12)
	if specID < 0 {
		return "", fmt.Errorf("invalid spec ID in hash")
	}

	// Find spec data in tree JSON
	var spec *ivSpecJSON
	for _, s := range tree.Specs {
		if s.ID == specID {
			sCopy := s
			spec = &sCopy
			break
		}
	}
	if spec == nil {
		return "", fmt.Errorf("spec ID %d not found in tree JSON", specID)
	}

	// Build node lookup maps for the current spec
	nodeTypes := map[int]string{}    // nodeID -> type
	nodeMaxRanks := map[int]int{}    // nodeID -> max ranks
	nodeMaxedOut := map[int]bool{}   // nodeID -> alreadyMaxedOut
	for _, n := range spec.ClassNodes {
		nodeTypes[n.ID] = n.Type
		nodeMaxRanks[n.ID] = n.Spells[0].MaxRanks
		nodeMaxedOut[n.ID] = n.AlreadyMaxedOut
	}
	for _, n := range spec.SpecNodes {
		nodeTypes[n.ID] = n.Type
		nodeMaxRanks[n.ID] = n.Spells[0].MaxRanks
		nodeMaxedOut[n.ID] = n.AlreadyMaxedOut
	}

	// Sorted node ID lists for hash replay
	classNodeIDs := sortedNodeIDs(spec.ClassNodes)
	specNodeIDs := sortedNodeIDs(spec.SpecNodes)

	// Replay class tree and spec tree actions
	classStates := replayActions(classStr, classNodeIDs, nodeTypes, nodeMaxRanks)
	specStates := replayActions(specStr, specNodeIDs, nodeTypes, nodeMaxRanks)

	// Replay apex talent actions
	apexMaxPoints := 0
	for _, sp := range spec.ApexNode.Spells {
		apexMaxPoints += sp.MaxRanks
	}
	apexPoints := 0
	if apexStr != "" {
		apexReader := newBitReader(apexStr, hashBase64Table)
		for apexReader.hasMore() {
			idx := apexReader.read(6)
			if idx < 0 {
				break
			}
			apexPoints++
		}
	}

	// Replay hero tree actions
	heroChoice := -1 // -1 = no hero tree
	heroStates := map[int]*nodeState{}
	var activeHeroNodeIDs []int
	if heroStr != "" {
		heroReader := newBitReader(heroStr, hashBase64Table)
		heroChoice = heroReader.read(1)
		if heroChoice < 0 {
			heroChoice = -1
		} else {
			var heroSide *ivHeroSide
			if heroChoice == 0 {
				heroSide = &spec.Hero.Left
			} else {
				heroSide = &spec.Hero.Right
			}
			activeHeroNodeIDs = sortedNodeIDs(heroSide.Nodes)
			for _, n := range heroSide.Nodes {
				nodeTypes[n.ID] = n.Type
				nodeMaxRanks[n.ID] = n.Spells[0].MaxRanks
			}

			// Continue reading from the same reader (hero choice bit was already consumed)
			for heroReader.hasMore() {
				nodeIndex := heroReader.read(6)
				if nodeIndex < 0 || nodeIndex >= len(activeHeroNodeIDs) {
					break
				}
				nodeID := activeHeroNodeIDs[nodeIndex]
				isChoice := nodeTypes[nodeID] == "choice"

				st, exists := heroStates[nodeID]
				if !exists {
					st = &nodeState{isChoice: isChoice}
					heroStates[nodeID] = st
				}
				if isChoice {
					ch := heroReader.read(1)
					if ch < 0 {
						break
					}
					st.choice = ch
					st.points = 1
				} else {
					st.points++
				}
			}
		}
	}

	// Build allNodeIds (all specs' nodes + unused + meta + apex, sorted)
	allSet := map[int]bool{}
	for _, uid := range tree.UnusedNodeIDs {
		allSet[uid] = true
	}
	for _, s := range tree.Specs {
		for _, n := range s.ClassNodes {
			allSet[n.ID] = true
		}
		for _, n := range s.SpecNodes {
			allSet[n.ID] = true
		}
		for _, n := range s.Hero.Left.Nodes {
			allSet[n.ID] = true
		}
		for _, n := range s.Hero.Right.Nodes {
			allSet[n.ID] = true
		}
		allSet[s.Hero.MetaNodeID] = true
		allSet[s.ApexNode.ID] = true
	}
	allNodeIDs := make([]int, 0, len(allSet))
	for id := range allSet {
		allNodeIDs = append(allNodeIDs, id)
	}
	sort.Ints(allNodeIDs)

	// Set of active hero node IDs for quick lookup
	activeHeroSet := map[int]bool{}
	for _, id := range activeHeroNodeIDs {
		activeHeroSet[id] = true
	}

	// Write WoW export binary
	w := newBitWriter(base64Table)
	w.write(2, 8)        // serialization version
	w.write(specID, 16)  // spec ID
	w.write(0, 128)      // unused hash

	for _, nodeID := range allNodeIDs {
		// Check if this is a special node
		if nodeID == spec.Hero.MetaNodeID {
			if heroChoice >= 0 {
				w.write(1, 1) // isSelected
				w.write(1, 1) // isPurchased
				w.write(0, 1) // isPartiallyRanked
				w.write(1, 1) // isChoice
				w.write(heroChoice, 2)
			} else {
				w.write(0, 1) // not selected
			}
			continue
		}

		if nodeID == spec.ApexNode.ID {
			if apexPoints == 0 {
				w.write(0, 1) // not selected
			} else if apexPoints < apexMaxPoints {
				w.write(1, 1) // isSelected
				w.write(1, 1) // isPurchased
				w.write(1, 1) // isPartiallyRanked
				w.write(apexPoints, 6)
				w.write(0, 1) // not choice
			} else {
				w.write(1, 1) // isSelected
				w.write(1, 1) // isPurchased
				w.write(0, 1) // not partially ranked
				w.write(0, 1) // not choice
			}
			continue
		}

		// Check if this node belongs to the current spec's class/spec/hero tree
		var st *nodeState
		if s, ok := classStates[nodeID]; ok {
			st = s
		} else if s, ok := specStates[nodeID]; ok {
			st = s
		} else if s, ok := heroStates[nodeID]; ok {
			st = s
		}

		// Permanently maxed out nodes (starter abilities)
		if nodeMaxedOut[nodeID] {
			w.write(1, 1) // isSelected
			w.write(0, 1) // isPurchased (free)
			continue
		}

		if st != nil && st.points > 0 {
			maxRank := nodeMaxRanks[nodeID]
			w.write(1, 1) // isSelected
			w.write(1, 1) // isPurchased
			if st.isChoice {
				w.write(0, 1) // not partially ranked
				w.write(1, 1) // isChoice
				w.write(st.choice, 2)
			} else if st.points < maxRank {
				w.write(1, 1) // isPartiallyRanked
				w.write(st.points, 6)
				w.write(0, 1) // not choice
			} else {
				w.write(0, 1) // not partially ranked (maxed)
				w.write(0, 1) // not choice
			}
			continue
		}

		// Not selected (wrong spec, inactive, non-selected hero tree, unused, etc.)
		w.write(0, 1)
	}

	return w.toExportString(), nil
}
