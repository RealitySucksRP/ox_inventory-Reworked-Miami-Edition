/*
 * RS Inventory - ox_inventory protocol adapter
 * Modified by RealitySucksRP on 2026-08-24. GPL-3.0.
 * ---------------------------------------------------------------------------
 * The RS UI (app.js) speaks qb-inventory's NUI protocol. This shim translates
 * between it and ox_inventory so the visual layer remains isolated from the
 * ox_inventory protocol and can be maintained independently.
 *
 * Contracts below were read from the shipped source, not assumed:
 *
 *   ox -> UI   every payload is nested under `data`:
 *                init            data = { locale, items, leftInventory, imagepath }
 *                setupInventory  data = { leftInventory, rightInventory }
 *                refreshSlots    data = { items, itemCount }
 *                itemNotify      data = [ slot, action, count ]
 *                closeInventory / toggleHotbar / displayMetadata
 *              ox inventory shape: { id, slots, items, maxWeight, label, type }
 *              ox slot shape:      { slot, name, count, weight, metadata, durability }
 *
 *   UI <- shim  flat payloads, only these 7 actions are handled by app.js:
 *                open, close, update, toggleHotbar, itemBox,
 *                requiredItem, setServerTime
 *              qb slot shape: { slot, name, amount, label, weight, info, image }
 *
 *   UI -> ox   app.js posts with AXIOS (XMLHttpRequest), not fetch, to
 *              https://qb-inventory/<Endpoint>. axios.post is therefore what
 *              gets intercepted here -- hooking window.fetch would never fire.
 *
 * Load order: after axios, before app.js.
 */
(function () {
    'use strict';

    var OX = 'ox_inventory';

    var itemRegistry = {};
    var imagePath = 'nui://ox_inventory/web/images';
    var metadataDisplay = [];
    var imageAliases = window.__rsImageAliases || {};

    // Exposed read-only helpers for the custom Vue tooltip layer. ox_inventory's
    // displayMetadata export sends human labels/order separately from each slot,
    // so the adapter retains that UI contract instead of discarding it.
    window.__rsOxDisplayMetadata = metadataDisplay;

    // app.js replaces its entire inventory on `update`, but ox sends slot
    // deltas. Mirror both sides here so a delta can be expanded into a full set.
    var mirror = { left: {}, right: {}, leftMeta: null, rightMeta: null };
    var hotbarOpen = false;

    var oxNativeActions = {
        init: true,
        setupInventory: true,
        refreshSlots: true,
        closeInventory: true,
        itemNotify: true,
        toggleHotbar: true,
        displayMetadata: true
    };

    // ---------------------------------------------------------------- helpers

    function oxPost(endpoint, body) {
        return fetch('https://' + OX + '/' + endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body === undefined ? {} : body)
        }).then(function (r) {
            return r.json().catch(function () { return null; });
        });
    }

    function send(action, payload) {
        var msg = { action: action };
        for (var k in payload) {
            if (Object.prototype.hasOwnProperty.call(payload, k)) msg[k] = payload[k];
        }
        window.postMessage(msg, '*');
    }

    function resolveOxImage(image, fallbackName) {
        var value = image || ((fallbackName || 'noimage') + '.png');
        value = String(value).trim();

        if (/^(?:https?:|data:|blob:)/i.test(value)) return value;

        // Item definitions with client.image arrive as a complete NUI URL.
        // Pull local ox paths back to a filename so legacy aliases can still be
        // applied; leave URLs owned by other resources untouched.
        if (/^nui:/i.test(value)) {
            var localNui = value.match(/^nui:\/\/ox_inventory\/web\/images\/(.+)$/i);
            if (!localNui) return value;
            value = localNui[1];
        }

        value = value
            .replace(/^\.\//, '')
            .replace(/^images\//i, '')
            .replace(/^web\/images\//i, '');

        value = imageAliases[String(value).toLowerCase()] || value;

        return String(imagePath || 'nui://ox_inventory/web/images').replace(/\/$/, '') + '/' + value;
    }


    function componentDescription(def) {
        if (!def) return '';
        if (def.description) return def.description;

        var type = String(def.type || '').toLowerCase();
        var labels = {
            muzzle: 'Muzzle attachment for compatible weapons.',
            flashlight: 'Weapon-mounted flashlight for compatible weapons.',
            grip: 'Grip attachment for compatible weapons.',
            barrel: 'Barrel attachment for compatible weapons.',
            magazine: 'Magazine attachment for compatible weapons.',
            sight: 'Optic / sight attachment for compatible weapons.',
            skin: 'Cosmetic weapon finish for compatible weapons.'
        };

        return labels[type] || (def.isComponent ? 'Weapon attachment for compatible weapons.' : '');
    }

    // ---------------------------------------------------- native component map
    //
    // ox stores installed attachments in metadata.components as ox ITEM names
    // (at_suppressor_light). rs-weaponshops additionally records the GTA native
    // names in metadata.rsws_native_components (COMPONENT_AT_PI_SUPP).
    //
    // Any weapon bought before the ox mapping worked has ONLY the native list,
    // so the attachment panel found nothing and drew every slot empty even
    // though the hover tooltip clearly showed the components. Resolving native
    // name -> joaat hash -> ox item makes those weapons display correctly, with
    // no re-purchase and no server change to their stored metadata.

    function joaat(text) {
        var h = 0;
        var str = String(text || '').toLowerCase();
        for (var i = 0; i < str.length; i++) {
            h = (h + str.charCodeAt(i)) >>> 0;
            h = (h + (h << 10)) >>> 0;
            h = (h ^ (h >>> 6)) >>> 0;
        }
        h = (h + (h << 3)) >>> 0;
        h = (h ^ (h >>> 11)) >>> 0;
        h = (h + (h << 15)) >>> 0;
        return h >>> 0;
    }

    // Lua backtick literals compile SIGNED once the high bit is set, so the same
    // component can arrive as -1899902599 or 2395064697. Compare unsigned only.
    function unsignedHash(value) {
        var n = Number(value);
        if (!isFinite(n)) return null;
        n = Math.trunc(n);
        if (n < 0) n += 4294967296;
        return n >>> 0;
    }

    var nativeComponentMap = null;

    function buildNativeComponentMap() {
        var map = {};
        for (var itemName in itemRegistry) {
            if (!Object.prototype.hasOwnProperty.call(itemRegistry, itemName)) continue;
            var list = itemRegistry[itemName] && itemRegistry[itemName].components;
            if (!Array.isArray(list)) continue;
            for (var i = 0; i < list.length; i++) {
                var h = unsignedHash(list[i]);
                if (h !== null) map[h] = itemName;
            }
        }
        return map;
    }

    /** GTA native component name -> ox item name, or null. */
    function itemForNativeComponent(nativeName) {
        if (!nativeName) return null;
        if (!nativeComponentMap) nativeComponentMap = buildNativeComponentMap();
        return nativeComponentMap[joaat(nativeName)] || null;
    }

    function componentInfo(component) {
        var def = itemRegistry[component] || {};
        return {
            component: component,
            attachment: component,
            label: def.label || component,
            type: def.type || null,
            weight: Number(def.weight) || 0,
            description: componentDescription(def),
            image: resolveOxImage(def.image, component)
        };
    }

    window.__rsOxResolveComponentInfo = componentInfo;

    // ox slot -> qb slot
    function toQbSlot(s) {
        if (!s || !s.name) return null;

        var def = itemRegistry[s.name] || {};
        var meta = Object.assign({}, s.metadata || {});
        var amount = s.count != null ? s.count : (s.amount != null ? s.amount : 1);

        // The RS UI already knows how to render qb-style `info.quality`. ox
        // weapons normally store percentage durability in metadata; only copy a
        // 0..100 value so timestamp-based degrade metadata is never mislabelled.
        var durability = s.durability != null ? s.durability : meta.durability;
        if (meta.quality == null && Number(durability) >= 0 && Number(durability) <= 100) {
            meta.quality = Number(durability);
        }

        // UNIT vs STACK weight. ox sends slot.weight as the weight of the whole
        // stack -- Inventory.SlotWeight multiplies item.weight by slot.count and
        // adds loaded ammo -- but the qb shape app.js consumes expects PER-UNIT
        // weight, because app.js multiplies by `amount` itself when it totals an
        // inventory and when it gates a transfer. Passing the stack weight
        // through unchanged squares the weight by stack size, so a large stack
        // reports an impossible total and can never be moved back out of a
        // container. ox's own UI divides the same way (weight / count).
        var stackWeight = s.weight != null ? s.weight : null;
        var unitWeight = stackWeight !== null && amount > 0
            ? stackWeight / amount
            : (def.weight || 0);

        return {
            slot: s.slot,
            name: s.name,
            amount: amount,
            label: meta.label || def.label || s.name,
            weight: unitWeight,
            // qb reads item extras from `info`; ox stores them in `metadata`.
            info: meta,
            metadata: meta,
            description: meta.description || def.description || componentDescription(def),
            durability: durability,
            type: def.type,
            isComponent: !!def.isComponent,
            // ox expresses uniqueness as stack=false; the QB-shaped UI expects
            // the inverse `unique` flag when deciding whether slots may merge.
            unique: def.stack === false,
            useable: true,
            image: resolveOxImage(meta.image || def.image, s.name)
        };
    }

    // ox inventory.items (array or map) -> qb slot map keyed by slot number
    function toQbSlots(items) {
        var out = {};
        if (!items) return out;

        var list = Array.isArray(items) ? items : Object.keys(items).map(function (k) { return items[k]; });

        for (var i = 0; i < list.length; i++) {
            var q = toQbSlot(list[i]);
            if (q && Number(q.slot) > 0) out[Number(q.slot)] = q;
        }

        return out;
    }

    // app.js decides "is this a shop?" from otherInventoryName.startsWith('shop-')
    function otherName(inv) {
        if (!inv) return '';
        var id = inv.id != null ? String(inv.id) : '';
        if (inv.type === 'shop') return id.indexOf('shop-') === 0 ? id : ('shop-' + id);
        return id || inv.type || 'drop';
    }

    function shouldExposeOther(inv) {
        if (!inv) return false;

        // ox_inventory uses an empty `newdrop` as the default right inventory
        // even when the player only opened their own inventory. Do not render a
        // fake/empty container in that state. The moment an item is actually
        // dropped, mirror.right gains a slot and the ground-drop pane appears.
        if (inv.type === 'newdrop') {
            return Object.keys(mirror.right || {}).length > 0;
        }

        return true;
    }

    function otherBlock(inv) {
        if (!shouldExposeOther(inv)) return null;
        return {
            inventory: mirror.right,
            name: otherName(inv),
            label: inv.label || inv.id || (inv.type === 'newdrop' ? 'Ground' : 'Container'),
            maxweight: inv.maxWeight,
            slots: inv.slots
        };
    }

    // ------------------------------------------------------- inbound: ox -> UI

    window.addEventListener('message', function (event) {
        var msg = event.data;
        if (!msg || !msg.action) return;

        // Ignore the messages this shim itself emits, or infinite loop.
        if (msg.__rs) return;

        // This adapter is registered before app.js. Stop ox-native messages
        // here so the QB-style Vue listener never sees setupInventory/init and
        // logs them as unexpected actions. The translated __rs message posted
        // below is allowed through normally.
        if (oxNativeActions[msg.action] && event.stopImmediatePropagation) {
            event.stopImmediatePropagation();
        }

        var d = msg.data || {};

        switch (msg.action) {
            case 'init':
                itemRegistry = d.items || {};
                nativeComponentMap = null; // registry replaced; rebuild lazily
                if (d.imagepath) imagePath = String(d.imagepath).replace(/\/$/, '');

                if (d.leftInventory) {
                    mirror.leftMeta = d.leftInventory;
                    mirror.left = toQbSlots(d.leftInventory.items);
                }

                // app.js expects a server clock for decay/expiry support; ox
                // does not provide one, so seed it from the client.
                send('setServerTime', { __rs: 1, serverTime: Math.floor(Date.now() / 1000) });
                break;

            case 'setupInventory':
                mirror.leftMeta = d.leftInventory || mirror.leftMeta;
                mirror.rightMeta = d.rightInventory || null;
                mirror.left = toQbSlots(mirror.leftMeta && mirror.leftMeta.items);
                mirror.right = toQbSlots(mirror.rightMeta && mirror.rightMeta.items);

                send('open', {
                    __rs: 1,
                    inventory: mirror.left,
                    label: mirror.leftMeta && mirror.leftMeta.label,
                    maxweight: mirror.leftMeta && mirror.leftMeta.maxWeight,
                    slots: mirror.leftMeta && mirror.leftMeta.slots,
                    other: otherBlock(mirror.rightMeta)
                });
                break;

            case 'refreshSlots':
                applyRefresh(d);
                send('update', {
                    __rs: 1,
                    inventory: mirror.left,
                    other: mirror.rightMeta ? otherBlock(mirror.rightMeta) : null
                });
                break;

            case 'closeInventory':
                send('close', { __rs: 1 });
                break;

            case 'itemNotify':
                // ox: data = [ slotData, 'added'|'removed', count ]
                var notifyType = d[1] || d.type;
                if (notifyType === 'added') notifyType = 'add';
                if (notifyType === 'removed') notifyType = 'remove';
                send('itemBox', {
                    __rs: 1,
                    item: toQbSlot(d[0] || d.item),
                    type: notifyType,
                    amount: d[2] || d.count
                });
                break;

            case 'toggleHotbar':
                if (typeof msg.data === 'boolean') {
                    hotbarOpen = msg.data;
                } else if (msg.data && typeof msg.data.state === 'boolean') {
                    hotbarOpen = msg.data.state;
                } else {
                    hotbarOpen = !hotbarOpen;
                }

                var hotbarItems = [];
                for (var hotbarSlot = 1; hotbarSlot <= 5; hotbarSlot++) {
                    hotbarItems.push(mirror.left[hotbarSlot] || null);
                }

                send('toggleHotbar', { __rs: 1, open: hotbarOpen, items: hotbarItems });
                break;

            case 'displayMetadata':
                // ox_inventory uses this message to define friendly metadata labels
                // and ordering (e.g. `vin` -> `VIN`, `serial` -> `Serial Number`).
                // The previous adapter swallowed it, so custom metadata appeared as
                // raw keys or not at all in the RS hover card.
                metadataDisplay = Array.isArray(d) ? d.slice() : [];
                window.__rsOxDisplayMetadata = metadataDisplay;
                break;
        }
    });

    // ox refreshSlots carries slot deltas rather than a whole inventory.
    // Entries look like { item: <slot>, inventory: 'player' | 'shop' | ... }.
    // An entry whose item has no name means the slot was emptied.
    function applyRefresh(d) {
        var entries = d.items;
        if (entries) {
            if (!Array.isArray(entries)) entries = [entries];

            for (var i = 0; i < entries.length; i++) {
                var entry = entries[i];
                if (!entry) continue;

                var raw = entry.item || entry;
                var slotNum = Number(raw.slot);
                if (!slotNum) continue;

                var inventoryKey = entry.inventory;
                var isLeft = !inventoryKey
                    || inventoryKey === 'player'
                    || (mirror.leftMeta && String(inventoryKey) === String(mirror.leftMeta.id))
                    || (mirror.leftMeta && String(inventoryKey) === String(mirror.leftMeta.type));
                var isRight = inventoryKey === 'shop'
                    || (mirror.rightMeta && String(inventoryKey) === String(mirror.rightMeta.id))
                    || (mirror.rightMeta && String(inventoryKey) === String(mirror.rightMeta.type));

                var target = isRight && !isLeft ? mirror.right : mirror.left;

                if (!raw.name) {
                    delete target[slotNum];
                } else {
                    var q = toQbSlot(raw);
                    if (q) target[slotNum] = q;
                }
            }
        }

        // Newer ox_inventory refreshSlots payloads can update max weight or
        // slot capacity without reopening the inventory. Mirror those fields so
        // the redesigned headers and grids remain accurate.
        if (d.weightData) {
            var weightId = d.weightData.inventoryId;
            if (mirror.leftMeta && String(mirror.leftMeta.id) === String(weightId)) {
                mirror.leftMeta.maxWeight = d.weightData.maxWeight;
            } else if (mirror.rightMeta && String(mirror.rightMeta.id) === String(weightId)) {
                mirror.rightMeta.maxWeight = d.weightData.maxWeight;
            }
        }

        if (d.slotsData) {
            var slotsId = d.slotsData.inventoryId;
            if (mirror.leftMeta && String(mirror.leftMeta.id) === String(slotsId)) {
                mirror.leftMeta.slots = d.slotsData.slots;
            } else if (mirror.rightMeta && String(mirror.rightMeta.id) === String(slotsId)) {
                mirror.rightMeta.slots = d.slotsData.slots;
            }
        }
    }

    // ------------------------------------------------------ outbound: UI -> ox

    function inventoryTypeForUi(name) {
        if (name === 'player' || name === undefined || name === null || name === '') {
            return (mirror.leftMeta && mirror.leftMeta.type) || 'player';
        }

        return (mirror.rightMeta && mirror.rightMeta.type) || String(name);
    }

    function weaponAttachments(item) {
        var info = (item && (item.info || item.metadata)) || {};
        var components = Array.isArray(info.components) ? info.components : [];

        // Fallback for weapons that only carry the native component list.
        if (!components.length && Array.isArray(info.rsws_native_components)) {
            var resolved = [];
            for (var n = 0; n < info.rsws_native_components.length; n++) {
                var mapped = itemForNativeComponent(info.rsws_native_components[n]);
                if (mapped && resolved.indexOf(mapped) === -1) resolved.push(mapped);
            }
            components = resolved;
        }

        var out = [];

        for (var i = 0; i < components.length; i++) {
            var raw = components[i];
            var component = typeof raw === 'string'
                ? raw
                : (raw && (raw.component || raw.attachment || raw.name));
            if (!component) continue;

            var infoDef = componentInfo(component);
            out.push({
                attachment: component,
                component: component,
                label: infoDef.label,
                type: infoDef.type,
                weight: infoDef.weight,
                description: infoDef.description,
                image: infoDef.image,
                slot: item && item.slot
            });
        }

        return out;
    }

    var routes = {
        CloseInventory: function () {
            return oxPost('exit', {});
        },
        UseItem: function (b) {
            var slot = b && b.slot != null
                ? b.slot
                : (b && b.item && b.item.slot != null ? b.item.slot : b);
            return oxPost('useItem', slot);
        },
        GiveItem: function (b) {
            return oxPost('giveItem', {
                slot: b && b.slot != null ? Number(b.slot) : Number(b && b.item && b.item.slot),
                count: Math.max(1, Number(b && (b.count != null ? b.count : b.amount)) || 1)
            });
        },
        AttemptPurchase: function (b) {
            var item = (b && b.item) || {};
            return oxPost('buyItem', {
                fromSlot: Number(b && b.fromSlot != null ? b.fromSlot : item.slot),
                toSlot: Number(b && b.toSlot != null ? b.toSlot : 1),
                fromType: (mirror.rightMeta && mirror.rightMeta.type) || 'shop',
                toType: (mirror.leftMeta && mirror.leftMeta.type) || 'player',
                count: Math.max(1, Number(b && (b.amount != null ? b.amount : b.count)) || 1)
            });
        },
        GetWeaponData: function (b) {
            var requested = (b && b.ItemData) || (b && b.item) || {};
            var slot = Number(requested.slot);
            var item = (slot && mirror.left[slot]) || requested;
            return Promise.resolve({
                WeaponData: item,
                AttachmentData: weaponAttachments(item)
            });
        },
        RemoveAttachment: function (b) {
            var attachment = (b && b.AttachmentData) || {};
            var weapon = (b && b.WeaponData) || {};
            var component = attachment.component || attachment.attachment || attachment.name;
            var slot = Number(weapon.slot);
            if (!component || !slot) {
                return Promise.resolve({ ok: false, error: 'invalid_attachment' });
            }

            return oxPost('removeComponent', {
                slot: slot,
                component: component
            }).then(function () {
                // ox acknowledges the NUI callback before the server mutation is
                // finished. Wait for refreshSlots so the panel reflects the real
                // weapon metadata instead of optimistically hiding an attachment
                // that may have failed to detach.
                return new Promise(function (resolve) {
                    var tries = 0;
                    function check() {
                        tries += 1;
                        var latest = mirror.left[slot] || weapon;
                        var remaining = weaponAttachments(latest);
                        var stillInstalled = remaining.some(function (entry) {
                            return entry.component === component;
                        });

                        if (!stillInstalled) {
                            resolve({ ok: true, WeaponData: latest, Attachments: remaining });
                            return;
                        }

                        if (tries >= 20) {
                            resolve({ ok: false, error: 'attachment_remove_not_confirmed', WeaponData: latest, Attachments: remaining });
                            return;
                        }

                        setTimeout(check, 50);
                    }
                    setTimeout(check, 50);
                });
            });
        },
        // A drop in ox is a swap into a `newdrop` inventory, not its own call.
        DropItemFromUI: function (b) {
            return oxPost('swapItems', {
                fromSlot: Number(b && b.fromSlot != null ? b.fromSlot : b && b.slot),
                toSlot: Number(b && b.toSlot != null ? b.toSlot : 1),
                count: Math.max(1, Number(b && (b.amount != null ? b.amount : b.count)) || 1),
                fromType: (mirror.leftMeta && mirror.leftMeta.type) || 'player',
                toType: 'newdrop'
            });
        },
        SetInventoryData: function (b) {
            return oxPost('swapItems', {
                fromSlot: Number(b && b.fromSlot),
                toSlot: Number(b && b.toSlot),
                count: Math.max(1, Number(b && (b.toAmount != null ? b.toAmount : (b.count != null ? b.count : b.amount))) || 1),
                fromType: inventoryTypeForUi(b && (b.fromInventory || b.fromType)),
                toType: inventoryTypeForUi(b && (b.toInventory || b.toType))
            });
        },
        PlayDropFail: function () {
            return Promise.resolve(null);
        }
    };

    function routeFor(url) {
        var m = String(url || '').match(/\/([A-Za-z]+)$/);
        return m ? routes[m[1]] : null;
    }

    // app.js uses axios (XHR). Wrap axios.post so those calls reach ox, and
    // return an axios-shaped { data } so callers reading `res.data` still work.
    function installAxiosHook() {
        if (typeof window.axios === 'undefined' || !window.axios.post) return false;

        var nativePost = window.axios.post.bind(window.axios);

        window.axios.post = function (url, body, config) {
            var handler = routeFor(url);
            if (!handler) return nativePost(url, body, config);

            return handler(body || {}).then(function (result) {
                return { data: result === undefined ? null : result, status: 200 };
            });
        };

        return true;
    }

    if (!installAxiosHook()) {
        // axios not parsed yet; retry once the document is ready.
        document.addEventListener('DOMContentLoaded', installAxiosHook);
    }

    // Belt and braces: catch any direct fetch calls to the qb endpoints too.
    var nativeFetch = window.fetch.bind(window);
    window.fetch = function (input, init) {
        var url = typeof input === 'string' ? input : (input && input.url) || '';
        var handler = url.indexOf(OX) === -1 ? routeFor(url) : null;

        if (handler) {
            var body = {};
            if (init && init.body) {
                try { body = JSON.parse(init.body); } catch (e) { body = {}; }
            }
            return handler(body).then(function (result) {
                return new Response(JSON.stringify(result === undefined ? null : result), {
                    status: 200,
                    headers: { 'Content-Type': 'application/json' }
                });
            });
        }

        return nativeFetch(input, init);
    };

    // ox withholds `init` until the UI reports ready, so signalling too early
    // loses the payload: app.js is deferred and registers its message listener
    // when Vue mounts. Wait for `load` (after deferred scripts have run) plus a
    // tick, so the listener is definitely attached before ox replies.
    function signalReady() {
        setTimeout(function () { oxPost('uiLoaded', {}); }, 50);
    }

    if (document.readyState === 'complete') {
        signalReady();
    } else {
        window.addEventListener('load', signalReady);
    }
})();
