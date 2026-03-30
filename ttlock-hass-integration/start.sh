#!/usr/bin/env bashio

export MQTT_HOST=$(bashio::services mqtt "host")
export MQTT_PORT=$(bashio::services mqtt "port")
export MQTT_SSL=$(bashio::services mqtt "ssl")
export MQTT_USER=$(bashio::services mqtt "username")
export MQTT_PASS=$(bashio::services mqtt "password")
export GATEWAY=$(bashio::config "gateway")
export GATEWAY_HOST=$(bashio::config "gateway_host")
export GATEWAY_PORT=$(bashio::config "gateway_port")
export GATEWAY_KEY=$(bashio::config "gateway_key")
export GATEWAY_USER=$(bashio::config "gateway_user")
export GATEWAY_PASS=$(bashio::config "gateway_pass")
if $(bashio::config.true "ignore_crc"); then
  echo "IGNORE CRC TRUE"
  export TTLOCK_IGNORE_CRC=1
fi
if $(bashio::config.equals "gateway" "noble"); then
  echo "Disable noble auto-binding"
  export NOBLE_WEBSOCKET=1
fi
if $(bashio::config.true "debug_communication"); then
  echo "Debug communication ON"
  export TTLOCK_DEBUG_COMM=1
fi
if $(bashio::config.true "debug_mqtt"); then
  echo "Debug MQTT"
  export MQTT_DEBUG=1
fi
if $(bashio::config.true "gateway_debug"); then
  echo "Debug gateway"
  export WEBSOCKET_DEBUG=1
fi

echo "Applying SDK patches..."
node -e "
const fs = require('fs');

// Patch 1: UUID filter for BLE scanning
let bleSvc = fs.readFileSync('/app/node_modules/ttlock-sdk-js/dist/scanner/BluetoothLeService.js', 'utf8');
if (!bleSvc.includes('021a9004')) {
  bleSvc = bleSvc.replace(
    'exports.TTLockUUIDs = [\"1910\", \"00001910-0000-1000-8000-00805f9b34fb\"]',
    'exports.TTLockUUIDs = [\"1910\", \"00001910-0000-1000-8000-00805f9b34fb\", \"021a9004-0382-4aea-bff4-6b3f1c5adfb4\", \"7aebf330-6cb1-46e4-b23b-7cc2262c605e\"]'
  );
  fs.writeFileSync('/app/node_modules/ttlock-sdk-js/dist/scanner/BluetoothLeService.js', bleSvc);
  console.log('Patch 1: UUID filter');
}

// Patch 2: Default lockType + address for devices without manufacturerData
let btDev = fs.readFileSync('/app/node_modules/ttlock-sdk-js/dist/device/TTBluetoothDevice.js', 'utf8');
if (!btDev.includes('LOCK_TYPE_V3 fallback')) {
  btDev = btDev.replace(
    'if (this.device.manufacturerData.length >= 15) {\n                this.parseManufacturerData(this.device.manufacturerData);\n            }',
    'if (this.device.manufacturerData.length >= 15) {\n                this.parseManufacturerData(this.device.manufacturerData);\n            } else {\n                const Lock_fb = require(\"../constant/Lock\");\n                if (this.lockType === Lock_fb.LockType.UNKNOWN) {\n                    this.lockType = Lock_fb.LockType.LOCK_TYPE_V3;\n                    this.protocolType = 5;\n                    this.protocolVersion = 3;\n                    if (!this.address && this.id) {\n                        this.address = this.id.match(/.{2}/g).join(\":\").toUpperCase();\n                    }\n                    console.log(\"Applied LOCK_TYPE_V3 fallback for: \" + this.address);\n                }\n            }'
  );
  fs.writeFileSync('/app/node_modules/ttlock-sdk-js/dist/device/TTBluetoothDevice.js', btDev);
  console.log('Patch 2: lockType fallback + address');
}

// Patch 3: Increase SDK connect timeout from 10s to 30s
let nobleDev = fs.readFileSync('/app/node_modules/ttlock-sdk-js/dist/scanner/noble/NobleDevice.js', 'utf8');
if (!nobleDev.includes('timeout = 30')) {
  nobleDev = nobleDev.replace('async connect(timeout = 10)', 'async connect(timeout = 30)');
  fs.writeFileSync('/app/node_modules/ttlock-sdk-js/dist/scanner/noble/NobleDevice.js', nobleDev);
  console.log('Patch 3: connect timeout 30s');
}

// Patch 4: Expose unknown locks to API
let mgr = fs.readFileSync('/app/src/manager.js', 'utf8');
if (!mgr.includes('unknown lock also added to newLocks')) {
  mgr = mgr.replace(
    '    } else {\n      console.log(\"Discovered unknown lock:\", lock.toJSON());\n    }',
    '    } else {\n      console.log(\"Discovered unknown lock (adding to newLocks):\", lock.toJSON());\n      if (!this.newLocks.has(lock.getAddress())) {\n        this.newLocks.set(lock.getAddress(), lock);\n        listChanged = true;\n      }\n    }'
  );
  fs.writeFileSync('/app/src/manager.js', mgr);
  console.log('Patch 4: expose unknown locks');
}

// Patch 5: Service UUID fallback -- try 7aebf330 as the lock data service
// Also add GATT dump logging to subscribe() to see all service characteristics
btDev = fs.readFileSync('/app/node_modules/ttlock-sdk-js/dist/device/TTBluetoothDevice.js', 'utf8');
if (!btDev.includes('7aebf330')) {
  // Replace the subscribe service lookup to try all known TTLock service UUIDs
  btDev = btDev.replace(
    'if (this.device.services.has(\"1910\")) {\n                service = this.device.services.get(\"1910\");\n            }',
    '// GATT dump: log all discovered services and their characteristics\n            for (let [svcUuid, svc] of this.device.services) {\n                console.log(\"GATT Service: \" + svcUuid);\n                if (svc.characteristics && svc.characteristics.size === 0) {\n                    await svc.readCharacteristics();\n                }\n                for (let [charUuid, chr] of svc.characteristics) {\n                    console.log(\"  Char: \" + charUuid + \" props: \" + JSON.stringify(chr.properties));\n                }\n            }\n            if (this.device.services.has(\"1910\")) {\n                service = this.device.services.get(\"1910\");\n            } else if (this.device.services.has(\"7aebf330-6cb1-46e4-b23b-7cc2262c605e\")) {\n                service = this.device.services.get(\"7aebf330-6cb1-46e4-b23b-7cc2262c605e\");\n                console.log(\"Using 7aebf330 service as lock data service\");\n            } else if (this.device.services.has(\"021a9004-0382-4aea-bff4-6b3f1c5adfb4\")) {\n                service = this.device.services.get(\"021a9004-0382-4aea-bff4-6b3f1c5adfb4\");\n                console.log(\"Using 021a9004 service (Espressif provisioning)\");\n            }'
  );
  // Also fix sendCommand
  btDev = btDev.replace(
    'const service = (_a = this.device) === null || _a === void 0 ? void 0 : _a.services.get(\"1910\");',
    'let service = (_a = this.device) === null || _a === void 0 ? void 0 : _a.services.get(\"1910\");\n            if (!service) { service = (_a = this.device) === null || _a === void 0 ? void 0 : _a.services.get(\"7aebf330-6cb1-46e4-b23b-7cc2262c605e\"); }\n            if (!service) { service = (_a = this.device) === null || _a === void 0 ? void 0 : _a.services.get(\"021a9004-0382-4aea-bff4-6b3f1c5adfb4\"); }'
  );
  fs.writeFileSync('/app/node_modules/ttlock-sdk-js/dist/device/TTBluetoothDevice.js', btDev);
  console.log('Patch 5: GATT dump + 7aebf330 service fallback');
}
"

cd /app
npm start
