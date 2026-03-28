---
name: publish
description: Full ADHDBiS release - git, GitHub, CurseForge, website deploy
user-invocable: true
---

# ADHDBiS Full Release

Perform a complete release of the ADHDBiS addon. Follow ALL steps in order. Do NOT skip any step.

## Pre-flight
- Read the current version from `addon/ADHDBiS/ADHDBiS.toc`
- Read the current companion app version from `updater/main.go` (CompanionVersion const)
- Increment addon PATCH version by 1 (e.g. 1.5.2 -> 1.5.3) unless user specifies otherwise
- If companion app (Go code) changed: increment companion app version separately (e.g. 1.5 -> 1.6)
- If ONLY addon changed: do NOT change companion app version
- Print a summary of what will be done and what changes are being released (based on git diff since last tag)

## Step 1: Pre-load BiS Data (CRITICAL)
- BEFORE creating the zip, run the companion app to scrape ALL classes from BOTH sources and generate fresh ADHDBiS_Data.lua:
  ```
  cd updater
  go build -o adhdbis-updater .
  echo -e "3\n0\n\n" | ./adhdbis-updater --cli
  ```
  This selects: [3] Both (Icy Veins + Wowhead), [0] All classes, then Enter to confirm.
  Wait for scrape to finish (~5-10 minutes for all 40 specs from both sources).
- The generated file goes to the WoW AddOns folder. Copy it back to source:
  ```
  cp "/Volumes/Samsung 1TB/World of Warcraft/_retail_/Interface/AddOns/ADHDBiS/ADHDBiS_Data.lua" addon/ADHDBiS/ADHDBiS_Data.lua
  ```
- Verify `addon/ADHDBiS/ADHDBiS_Data.lua` has fresh data: `head -3 addon/ADHDBiS/ADHDBiS_Data.lua` should show today's date and "Source: Both"
- This ensures users have BiS data from BOTH sources THE INSTANT they install the addon
- IMPORTANT: Always scrape BOTH sources (option 3), never just one

## Step 2: Website Audit
- Read `www/index.html` and compare feature descriptions, commands table, and version number against actual addon code
- Fix any outdated descriptions, missing commands, or wrong version numbers
- Update version number on website

## Step 3: Build Artifacts
- Update addon version in `addon/ADHDBiS/ADHDBiS.toc`
- If companion app changed: update CompanionVersion in `updater/main.go` (const + banner) - generator picks it up automatically
- Create addon zip (MUST include ADHDBiS_Data.lua from Step 1):
  ```
  cd addon && rm -f ADHDBiS.zip && zip -r ADHDBiS.zip ADHDBiS/ -x "*.DS_Store"
  ```
- Verify ADHDBiS_Data.lua is IN the zip: `unzip -l addon/ADHDBiS.zip | grep Data.lua`
- Build ALL platform binaries into `updater/binary/`:
  ```
  cd updater
  GOOS=darwin GOARCH=arm64 go build -o binary/adhdbis-updater-mac-arm64 .
  GOOS=darwin GOARCH=amd64 go build -o binary/adhdbis-updater-mac-amd64 .
  GOOS=windows GOARCH=amd64 go build -o binary/adhdbis-updater.exe .
  GOOS=linux GOARCH=amd64 go build -o binary/adhdbis-updater-linux .
  ```
- Copy updated addon files to WoW: `cp addon/ADHDBiS/*.lua addon/ADHDBiS/*.toc "/Volumes/Samsung 1TB/World of Warcraft/_retail_/Interface/AddOns/ADHDBiS/"`

## Step 4: Changelog
- Add new entry to `www/changelog.html` with version, date, and changes
- Move "Latest" tag from previous version to new version
- Update `README.md` if new commands or features were added

## Step 5: Git + GitHub Release
- `git add` all changed files (addon, website, README, binaries)
- `git commit` with message: `vX.Y.Z - <short description>`
- `git push`
- `gh release create vX.Y.Z` with release notes and ALL 5 assets:
  - `addon/ADHDBiS.zip`
  - `updater/binary/adhdbis-updater.exe`
  - `updater/binary/adhdbis-updater-mac-arm64`
  - `updater/binary/adhdbis-updater-mac-amd64`
  - `updater/binary/adhdbis-updater-linux`

## Step 6: CurseForge
- IMPORTANT: Changelog must APPEND new version on top of existing changelog, never replace it
- Upload to CurseForge with changelog and displayName:
  ```
  cat > /tmp/cf_metadata.json << 'JSONEOF'
  {"changelog":"CUMULATIVE_CHANGELOG_HERE","displayName":"ADHDBiS X.Y.Z","releaseType":"release","gameVersions":[15855]}
  JSONEOF
  curl -s -X POST "https://wow.curseforge.com/api/projects/1492799/upload-file" \
    -H "X-Api-Token: 62d60221-94cc-4749-afa6-ca180d0e8b8f" \
    -F "metadata=</tmp/cf_metadata.json" -F "file=@addon/ADHDBiS.zip"
  ```

## Step 7: Website Deploy
- Deploy to production:
  ```
  sshpass -p 'Phoenix.' ssh nenadjokic@docker.local "rm -rf /tmp/adhd_deploy && mkdir -p /tmp/adhd_deploy/images"
  sshpass -p 'Phoenix.' scp www/index.html www/changelog.html nenadjokic@docker.local:/tmp/adhd_deploy/
  sshpass -p 'Phoenix.' scp www/images/* nenadjokic@docker.local:/tmp/adhd_deploy/images/
  sshpass -p 'Phoenix.' ssh nenadjokic@docker.local "echo 'Phoenix.' | sudo -S bash -c 'cp /tmp/adhd_deploy/index.html /tmp/adhd_deploy/changelog.html /home/nenadjokic/lamp_web/www/adhd/ && cp /tmp/adhd_deploy/images/* /home/nenadjokic/lamp_web/www/adhd/images/ && chown -R www-data:www-data /home/nenadjokic/lamp_web/www/adhd/'"
  ```

## Step 8: Summary
Print a final summary:
```
Nova verzija sa X.Y.Z na A.B.C
BiS data pre-loaded: YES (scraped [date], [N] specs)
Kreirani zip file za addon (sa ADHDBiS_Data.lua)
Kreirani novi binary fajlovi
Kratak summary sta je updateovano:
1. Addon: ...
2. Companion app: ...
3. Website: ...
4. BiS data: Fresh scrape from Icy Veins ([date])

Objavljeno:
- GitHub Release: <URL>
- CurseForge: Upload OK (ID: <id>)
- Website: https://adhd.jokicville.org - deploy OK
```

## IMPORTANT RULES
- NEVER create symlinks to WoW folder - always COPY files
- Binaries go ONLY in `updater/binary/` - never in `updater/` root
- CurseForge metadata MUST include `displayName` with version
- Always check for old version strings with grep after bumping version
- Website deploy uses FULL paths (not ~) because sudo runs as root
- ALWAYS pre-load BiS data before packaging (Step 1) - users must have data on install
- Addon zip in `addon/ADHDBiS.zip` - never in repo root
- PWA is a SEPARATE project at /Volumes/Samsung 1TB/wowadd/ADHDPWA/ - do NOT touch it during addon publish
