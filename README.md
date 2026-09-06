# RealitySucksRP Miami Edition — ox_inventory

### Miami-inspired FiveM inventory rework built from ox_inventory
<img width="2000" height="1125" alt="image" src="https://github.com/user-attachments/assets/a81f6022-cb5f-4359-9c70-0db17d11106e" />

<p align="center">
  <a href="https://reality-sucks-rp-webstore.tebex.io/category/enhanced"><img src="https://img.shields.io/badge/EXPLORE-ENHANCED%20RESOURCES-ff6a00?style=for-the-badge" alt="Explore RealitySucksRP Enhanced resources on Tebex"></a>
  <a href="https://realitysucksrp.github.io/"><img src="https://img.shields.io/badge/VISIT-REALITYSUCKSRP%20WEBSITE-111111?style=for-the-badge" alt="Visit RealitySucksRP website"></a>
  <a href="https://discord.gg/e9V3rPHySx"><img src="https://img.shields.io/badge/JOIN-DISCORD-5865F2?style=for-the-badge" alt="Join RealitySucksRP Discord"></a>
</p>

I love making FiveM scripts and running wild on GTA, but I also enjoy building complete servers. I use my own tested RealitySucksRP systems and configure server builds around the owner's gameplay, framework, economy, theme and direction.

## Miami Edition

This is my modified distribution of `ox_inventory` by Overextended with a custom RealitySucksRP Miami Edition interface and additional compatibility, inventory and gameplay work.

The goal is to keep the proven ox_inventory foundation while giving the inventory a more cinematic Miami-style presentation for modern RP servers.

## Highlights

- Miami-inspired cinematic inventory interface
- Responsive single- and dual-pane layouts
- Local/offline-safe NUI dependencies
- Drag and drop
- Quick move
- Shops
- Stashes
- Trunks and gloveboxes
- Ground drops
- Hotbar and notifications
- Metadata support
- Detailed hover cards with escaped metadata
- Weapon inspection with serial, condition, tint and attachment information
- Click-to-detach weapon components
- Resilient component removal when weapon metadata and ped state drift apart
- Expanded item catalogue
- Physical vehicle-key items
- Cash-as-item support
- Server-side inventory validation and authorization hardening

## Framework Support

The Miami Edition includes the upstream framework paths used by this ox_inventory base for:

- Qbox / `qbx_core`
- ESX
- `ox_core`
- `ND_Core`

This RealitySucksRP edition has also been tested in my FiveM Enhanced/Qbox environment with `qbx_core` and ox_inventory money-as-item configuration.

## Requirements

- FiveM server artifact 6116 or newer
- OneSync
- `oxmysql`
- `ox_lib`
- One supported framework

The resource folder must remain named:

```text
ox_inventory
```

For physical cash as an inventory item, ox_inventory can use its normal account configuration, for example:

```cfg
set inventory:accounts ["money"]
```

Only use money-as-item behavior when the rest of your framework and economy are configured for it.

## Enhanced RealitySucksRP Resources

I keep a separate Tebex category for RealitySucksRP resources that are currently listed for Enhanced compatibility/testing.

**Enhanced Tebex:** https://reality-sucks-rp-webstore.tebex.io/category/enhanced

**Full Store:** https://reality-sucks-rp-webstore.tebex.io/

**Website:** https://realitysucksrp.github.io/

## Complete FiveM Servers For Sale

Although I love making scripts and creating chaos in GTA, I also enjoy making complete FiveM servers.

I use tested RealitySucksRP systems and configure each build around what the server owner actually wants — gameplay, framework, economy, theme and overall direction.

- **QBCore Shell — $500**
- **Zombie Server — $700**
- **Full RP Server — $850**
- **30 days of Discord setup/support included**

**Server packages:** https://realitysucksrp.github.io/#packages

**Discord:** https://discord.gg/e9V3rPHySx

## Licence and Attribution

The original `ox_inventory` project is Copyright (C) 2021-2026 Linden, Luke, Dunak and contributors.

**Original source:** https://github.com/overextended/ox_inventory

This RealitySucksRP modification remains subject to the upstream GPL-3.0 licence. Preserve the original copyright, licence, attribution and modification notices when redistributing modified source.

GPL-3.0 applies to the program source covered by that licence and does not automatically grant rights to independently created artwork or other separately licensed assets.

---

**Reality Sucks. Build something memorable anyway.**
