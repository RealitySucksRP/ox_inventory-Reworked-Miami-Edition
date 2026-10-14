'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

let options;
const windowStub = {
    __rsOxDisplayMetadata: [],
    addEventListener() {},
    removeEventListener() {},
};

const sandbox = {
    Vue: {
        createApp(value) {
            options = value;
            return { use() { return this; }, mount() {} };
        },
    },
    FloatingVue: {},
    window: windowStub,
    document: {},
    console,
    setTimeout,
    clearTimeout,
};

const source = fs.readFileSync(path.resolve(__dirname, '../web/rs-ui/app.js'), 'utf8');
vm.runInNewContext(source, sandbox, { filename: 'app.js' });

const methods = options.methods;
const context = Object.assign({}, methods);

test('hover description and metadata HTML are escaped', () => {
    windowStub.__rsOxDisplayMetadata = [{ metadata: 'owner', value: '<Owner>' }];

    const html = methods.generateTooltipContent.call(context, {
        name: 'evidence',
        label: '<Evidence>',
        amount: 1,
        weight: 100,
        info: { owner: '<script>alert(1)</script>', description: '<img src=x onerror=alert(1)>' },
    });

    assert.match(html, /&lt;Evidence&gt;/);
    assert.match(html, /&lt;Owner&gt;/);
    assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
    assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt;/);
    assert.doesNotMatch(html, /<script>|<img src=x/);
});

test('opaque image metadata is hidden and long tooltip values are bounded', () => {
    windowStub.__rsOxDisplayMetadata = [
        { metadata: 'firstname', value: 'Firstname' },
        { metadata: 'mugShot', value: 'Mug Shot' },
    ];

    const longText = 'Long but readable '.repeat(40);
    const html = methods.generateTooltipContent.call(context, {
        name: 'driver_license',
        label: 'Drivers License',
        amount: 1,
        weight: 0,
        info: {
            firstname: 'Rob',
            mugShot: `data:image/png;base64,${'A'.repeat(5000)}`,
            opaqueBlob: 'B'.repeat(1000),
            notes: longText,
        },
    });

    assert.match(html, /Firstname:<\/span> Rob/);
    assert.doesNotMatch(html, /Mug Shot|data:image|opaqueBlob|Opaque Blob|A{100}|B{100}/);
    assert.match(html, /Long but readable/);
    assert.match(html, /…/);
    assert.doesNotMatch(html, new RegExp(longText));
});

test('stack identity includes metadata and ignores object key order', () => {
    const left = { name: 'water', unique: false, metadata: { quality: 80, batch: 'A' } };
    const same = { name: 'water', unique: false, metadata: { batch: 'A', quality: 80 } };
    const different = { name: 'water', unique: false, metadata: { batch: 'B', quality: 80 } };

    assert.equal(methods.sameStackIdentity.call(context, left, same), true);
    assert.equal(methods.sameStackIdentity.call(context, left, different), false);
});
