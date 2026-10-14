# RealitySucksRP ox_inventory — hover descriptions + attachment info patch

## Changed files
- client.lua
- web/rs-ui/rs-ox-adapter.js
- web/rs-ui/app.js
- web/rs-ui/index.html
- web/rs-ui/main.css

## What was fixed
- Hover tooltip now covers the full occupied item slot, not only the item image.
- Item descriptions prefer metadata description, then the ox item definition description, then a safe contextual fallback.
- ox `displayMetadata` friendly labels/order are retained and used in RS tooltips instead of being discarded by the adapter.
- Tooltip HTML is escaped before rendering metadata/description values.
- ox weapon durability (0-100) is normalised into the RS UI condition/quality display.
- Installed `metadata.components` are shown as named attachment chips instead of raw arrays.
- Attachment data now includes ox label, exact component type, weight, description/fallback description, image, and slot.
- Attachment classification prefers ox's actual component type; name matching is fallback only.
- Added a dedicated Barrel slot to Weapon Inspection.
- Filled attachment slots show the installed attachment's real label.
- Attachment hover explains label/type/weight/description and that clicking detaches it.
- GetWeaponData uses the latest mirrored weapon slot rather than a stale UI snapshot where possible.
- RemoveAttachment waits for ox refreshSlots confirmation instead of optimistically hiding the component before the server mutation completes.
- Equipped-weapon detach no longer depends on the ped visual component being perfectly in sync before authoritative metadata can be removed.

## Validation
- `web/rs-ui/app.js`: Node syntax check passed.
- `web/rs-ui/rs-ox-adapter.js`: Node syntax check passed.
- Adapter translation test passed for description + durability + metadata + 3 installed components.
- Tooltip generation test passed for friendly labels, description, condition, ammo and named attachments.
- Tooltip escaping test passed for HTML-like metadata/description strings.
- Attachment remove-confirmation test passed against a simulated ox `refreshSlots` update; remaining attachments stayed in sync.

## Live confirmation still needed
Run in FiveM and verify hover + attachment detach on at least one equipped and one unequipped weapon. The code has been statically/unit validated, but this patch is not yet live FiveM-confirmed.
