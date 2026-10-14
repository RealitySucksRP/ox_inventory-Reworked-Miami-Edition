# Changelog

## 2.47.9-rs-miami.8-qbx-production-guard - 2026-09-11

### Security and authority

- Revalidates secondary-inventory access during mutations instead of trusting an earlier open, including players, drops, stashes, evidence, containers, dumpsters, trunks and gloveboxes.
- Qbox vehicle storage capacity now resolves the network entity and model server-side and uses `qbx_core:GetVehicleClass`; client-provided class data is not authoritative on Qbox.
- Vehicle storage uses canonical exact plate matching, rejects invalid entities, rechecks routing buckets/distance/locks and fails closed when Qbox cannot resolve a class.
- Player searches use server-side Qbox `isdead`, `inlaststand` and `ishandcuffed` metadata plus the validated `canSteal` state, with distance and routing-bucket checks.
- Shop, crafting, give-item, weapon and license callbacks reject malformed payloads and revalidate the exact player inventory/session before commit.
- Weapon ammo/component mutations are bounded and backed by real inventory items; weapon slot weight changes now update total inventory weight.
- `SetMetadata` now validates/normalizes metadata before exposure and recalculates the exact slot-weight delta so ammo/components/custom weight metadata cannot desynchronise aggregate carry weight.
- Weapon-license purchases now require server-side proximity to the configured license point and successful payment.

### Persistence and transaction safety

- Database read failures are distinguished from legitimate empty inventory data; a temporary DB outage no longer creates an empty inventory that can overwrite stored data later.
- Failed player logout saves retain an in-memory recovery snapshot keyed by the stable character identifier and retry periodically; reconnects consume that snapshot before stale DB data.
- Individual and batch saves restore dirty state when persistence fails, and cleanup waits for in-flight saves.
- Player initialization no longer waits forever for a missing ped and restores a pending recovery snapshot if inventory creation fails.
- Crafting is server-timed, session/location/group checked, slot-locked and rollback protected across ingredient consumption and output creation.
- Shop purchases serialize stock/currency/destination state and restore both stock and the exact pre-purchase player inventory if commit fails.
- Give-item keeps destination-before-source safe ordering under inventory locks and validates both sessions/buckets/distance again after hooks.
- Confiscation and return now use oxmysql transactions as durable moves: recovery is keyed by owner + name, return merges with the live inventory instead of overwriting it, and recovery data is not deleted unless the merged player inventory persists successfully.
- Player teardown serializes against active slot transactions before its final save/remove, closing disconnect races with crafting, item use, weapon updates, give/shop actions and confiscation/return.
- Restored inventory NUI state now consumes the authoritative returned total weight correctly (with compatibility for the older tuple position).

### OneSync, UI and packaging

- Floor drops derive routing bucket and instance server-side, preserve bounded underwater seabed placement, continuously validate physical access and only replicate to players in the matching bucket/instance.
- Dumpster inventories are isolated by routing bucket.
- Forced/admin inventory views now set the same local `invOpen` lifecycle flag used by normal NUI focus cleanup.
- Removed deprecated `lua54 'yes'`; retained experimental OAL because it is a separate runtime option still used by this resource.
- Replaced the broad Miami UI files glob with explicit active HTML/CSS/JS/vendor/art paths and added `.PNG`/`.webp` image delivery. Backup/source documentation is no longer client-downloaded.
- Removed six reintroduced release residues: four `.bak` source backups and two Markdown files from `web/images`; no runtime file was removed.
- Added production regression coverage for the guards above.

### Compatibility notes

- This archive includes Qbox/QBX, ESX, ox_core and ND_Core bridges. It does not include a native QBCore or standalone bridge.
- The strongest vehicle-class authority in this release is Qbox-specific because Qbox exposes a server `GetVehicleClass(hash)` resolver. Other included bridges retain the upstream client class fallback when no server resolver exists.
- No external `rs_bridge` dependency was added.

## 2.47.9-rs-miami.7 - 2026-09-10

- Fixes the moving-vehicle ammo reload path throwing from `lib.waitFor` after its default ~1 second timeout.
- Prevents that throw from aborting before the authoritative `ox_inventory:updateWeapon` transaction, closing a free-ammo/client-server desync path.
- Uses a bounded non-throwing reload loop with `SetAmmoInClip` fallback while preserving the server-side ammo removal/update callback.

## 2.47.9-rs-miami.6 - Safe Transfer / Drop Loss Guard

### Fixed

- Player <-> secondary-inventory moves in the Miami UI are now server-authoritative.
  The UI no longer removes, adds, merges, swaps, or splits slot data before
  ox_inventory confirms the action through `refreshSlots`.
- A rejected lock/hook/distance/weight validation can no longer leave the custom
  UI showing a false empty slot that contaminates the next transfer.
- Ground-drop creation now creates the destination inventory before reducing the
  player source stack, closing a true item-loss edge case if destination creation
  ever fails.
- Existing server-side validation, slot locks, hooks, and anti-exploit checks remain
  enabled; this patch fixes rollback/authority ordering rather than weakening them.

### Validation

- Node syntax check passes for `web/rs-ui/app.js`.
- Security regression suite covers server-authoritative cross-inventory movement
  and drop destination-before-source ordering.

## 2.47.9-rs-miami.5 - Safe Metadata Tooltips

### Fixed

- Base64 mugshots, portraits, badges, and other opaque media metadata are no
  longer rendered as tooltip text on ID cards or any other inventory item.
- Unknown readable metadata remains visible, but individual values are capped
  at 240 characters and the tooltip scrolls within the screen instead of
  growing beyond the viewport.

## 2.47.9-rs-miami.4 - Package Audit

Audit pass over the fork. **No Lua was modified.** Changes are limited to one
malformed locale, the item image set, and dead files. Upstream ox_inventory code
is untouched so future merges from Overextended stay clean.

### Fixed

- **`locales/es.json` was invalid JSON** and failed to parse -- a trailing comma
  after `"storage"` on the last entry. Spanish was broken outright. All 30
  locales now parse.
- **8 item icons never reached clients.** They were saved with an uppercase
  `.PNG` extension, which does not match the `web/images/*.png` glob in
  `files{}` on a Linux server, so they were never sent at all: `junk`,
  `arena-war`, `best-customer`, `republican`, `rockfordhill`, `saw-skull`,
  `vinewoodrose`, `RobotBubblegum-trinket`. Renamed to lowercase `.png`.
- **3 `.webp` images could never load** (`phar`, `robs`, `Italdesign`) since the
  lookup is always `<item>.png`. Converted to PNG.
- **`suppressor_attachment.png.png`** was a 2.5 MB unprocessed source with a
  double extension. The correct 100x100 icon already existed at
  `suppressor_attachment.png`, so the mis-named copy was removed.

### Changed: client download cut from 85 MB to 34 MB

`web/images` went from 83.2 MB to 32.1 MB.

- 173 icons were between 100 KB and 2.5 MB at resolutions up to 1536x1024, while
  the established convention in this set is 100x100 and an inventory slot renders
  at 100 px. Capped at 256 px on the long edge, which still leaves 2.5x headroom
  for HiDPI. That alone saved 46.3 MB.
- Remaining icons were optimized losslessly.
- Verified afterwards: all 1,317 item, weapon, and component definitions still
  resolve to a real file through `web/rs-ui/image-aliases.js`. Zero regressions.

### Removed

- `web/rs-ui/main.css.bak` -- 36 KB, and because `files{}` uses
  `web/rs-ui/**/*` it was being downloaded by every client.
- `data/items.lua.suppressor.bak` -- 175 KB backup.
- `web/images/readme.md` and `web/images/jims-catcafe animations.md` -- non-image
  files in the image directory.

### Not changed, deliberately

- **`web/build/` was kept.** It is upstream's stock React UI, is not in `files{}`
  so costs clients nothing, and is the rollback path if the Miami UI ever breaks.
- **House ASCII/LF formatting was NOT applied.** This is a fork of an actively
  maintained upstream; reformatting 42 Lua files would make every future merge
  from Overextended painful for no runtime benefit.
- **1,963 orphan images (~15 MB after resizing) were kept.** They have no matching
  entry in `data/items.lua` or `data/weapons.lua`, but ox_inventory items can be
  registered at runtime by other resources, so they were reported rather than
  deleted. See the audit notes.

# Changelog

## 2.47.9-rs-miami.3 - 2026-08-24

- Updated server-side inventory validation and authorization.
- Consolidated Qbox physical cash configuration on ox_inventory's synchronized
  `money` item and removed the redundant catalogue-level `cash` definition.
- Improved Miami UI shop, give-item, metadata, and non-stack item synchronization.
- Improved player inventory initialization and general compatibility behavior.

## 2.47.9-rs-miami.2 - 2026-08-24

- Fixed startup abort caused by the upstream `init.lua` guard checking the
  removed stock `web/build/index.html` instead of the active Miami Edition
  entry point at `web/rs-ui/index.html`.
- Restored normal client/server initialization so exports such as `Items` can
  register for resources including `qbx_prison`.

## 2.47.9-rs-miami.1 - 2026-08-24

- Initial public-release preparation for the RealitySucksRP Miami Edition.
