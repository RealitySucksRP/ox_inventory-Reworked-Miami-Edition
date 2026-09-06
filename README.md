# RealitySucksRP Miami Edition — ox_inventory

### Miami-inspired FiveM inventory rework built from ox_inventory

<p align="center">
  <a href="https://reality-sucks-rp-webstore.tebex.io/category/enhanced"><img src="https://img.shields.io/badge/EXPLORE-ENHANCED%20RESOURCES-ff6a00?style=for-the-badge" alt="Explore RealitySucksRP Enhanced resources on Tebex"></a>
  <a href="https://realitysucksrp.github.io/"><img src="https://img.shields.io/badge/VISIT-REALITYSUCKSRP%20WEBSITE-111111?style=for-the-badge" alt="Visit RealitySucksRP website"></a>
  <a href="https://discord.gg/e9V3rPHySx"><img src="https://img.shields.io/badge/JOIN-DISCORD-5865F2?style=for-the-badge" alt="Join RealitySucksRP Discord"></a>
</p>

I love making FiveM scripts and running wild in GTA, but I also enjoy building complete servers. I use my own tested RealitySucksRP systems and configure server builds around the owner's gameplay, framework, economy, theme and direction.

## Miami Edition

This is a modified distribution of `ox_inventory` by Overextended with a custom RealitySucksRP Miami Edition interface and additional compatibility, inventory and gameplay work.

Highlights from the supplied Miami Edition build include:

- Miami-inspired cinematic inventory interface
- Responsive single- and dual-pane layouts
- Local/offline-safe NUI dependencies
- Drag and drop, quick move, shops, stashes, trunks, gloveboxes and drops
- Hotbar, notifications and metadata support
- Detailed hover cards with escaped metadata
- Weapon inspection with serial, condition, tint and attachment information
- Click-to-detach weapon component support
- Resilient weapon-component removal when metadata and ped state drift
- Expanded item catalogue
- Physical vehicle-key items
- Cash-as-item support
- Server-side inventory validation and authorization hardening

## Framework Support

The supplied archive includes upstream bridge support for:

- Qbox / `qbx_core`
- ESX
- `ox_core`
- `ND_Core`

The Miami Edition was tested on a FiveM Enhanced server using Qbox, `qbx_core` and `ox_inventory` money-as-item configuration.

## Requirements

- FiveM server artifact 6116 or newer
- OneSync
- `oxmysql`
- `ox_lib`
- One of the supported frameworks above

The resource folder must remain named `ox_inventory`.

For physical cash as an inventory item, use the normal ox_inventory account configuration, for example:

```cfg
set inventory:accounts ["money"]
```

Use that only when your framework/economy is configured for money-as-item behavior.

## Enhanced Resources

Browse RealitySucksRP resources currently listed for Enhanced compatibility/testing:

**Tebex Enhanced:** https://reality-sucks-rp-webstore.tebex.io/category/enhanced

## Complete FiveM Servers For Sale

Although I love building scripts and creating chaos in GTA, I also build complete FiveM servers.

I use tested RealitySucksRP systems and configure the stack around what the server owner actually wants.

- **QBCore Shell — $500**
- **Zombie Server — $700**
- **Full RP Server — $850**
- **30 days of Discord setup/support included**

**Website:** https://realitysucksrp.github.io/

**Tebex:** https://reality-sucks-rp-webstore.tebex.io/

**Discord:** https://discord.gg/e9V3rPHySx

## Licence and Attribution

The original `ox_inventory` project is Copyright (C) 2021-2026 Linden, Luke, Dunak and contributors.

**Original source:** https://github.com/overextended/ox_inventory

This RealitySucksRP modification remains subject to the upstream GPL-3.0 licence. Preserve the original copyright, licence, attribution and modification notices when redistributing modified source.

The supplied archive also includes an asset-provenance notice explaining that GPL-3.0 applies to program source and does not automatically grant rights to independently created artwork.

---

**Reality Sucks. Build something memorable anyway.**