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

// Patch 1: UUID filter
let bleSvc = fs.readFileSync('/app/node_modules/ttlock-sdk-js/dist/scanner/BluetoothLeService.js', 'utf8');
if (!bleSvc.includes('021a9004')) {
  bleSvc = bleSvc.replace(
    'exports.TTLockUUIDs = [\"1910\", \"00001910-0000-1000-8000-00805f9b34fb\"]',
    'exports.TTLockUUIDs = [\"1910\", \"00001910-0000-1000-8000-00805f9b34fb\", \"021a9004-0382-4aea-bff4-6b3f1c5adfb4\"]'
  );
  fs.writeFileSync('/app/node_modules/ttlock-sdk-js/dist/scanner/BluetoothLeService.js', bleSvc);
  console.log('Patched UUID filter');
}

// Patch 2: Default lockType AND address for devices without manufacturerData
let btDev = fs.readFileSync('/app/node_modules/ttlock-sdk-js/dist/device/TTBluetoothDevice.js', 'utf8');
if (!btDev.includes('LOCK_TYPE_V3 fallback')) {
  btDev = btDev.replace(
    'if (this.device.manufacturerData.length >= 15) {\n                this.parseManufacturerData(this.device.manufacturerData);\n            }',
    'if (this.device.manufacturerData.length >= 15) {\n                this.parseManufacturerData(this.device.manufacturerData);\n            } else {\n                // LOCK_TYPE_V3 fallback for locks advertising UUID without manufacturerData\n                const Lock_fb = require(\"../constant/Lock\");\n                if (this.lockType === Lock_fb.LockType.UNKNOWN) {\n                    this.lockType = Lock_fb.LockType.LOCK_TYPE_V3;\n                    this.protocolType = 5;\n                    this.protocolVersion = 3;\n                    // Derive address from device.id (MAC without colons)\n                    if (!this.address && this.id) {\n                        this.address = this.id.match(/.{2}/g).join(\":\").toUpperCase();\n                    }\n                    console.log(\"Applied LOCK_TYPE_V3 fallback for: \" + this.address);\n                }\n            }'
  );
  fs.writeFileSync('/app/node_modules/ttlock-sdk-js/dist/device/TTBluetoothDevice.js', btDev);
  console.log('Patched lockType fallback + address derivation');
}

// Patch 3: Increase SDK connect timeout from 10s to 30s
let nobleDev = fs.readFileSync('/app/node_modules/ttlock-sdk-js/dist/scanner/noble/NobleDevice.js', 'utf8');
if (!nobleDev.includes('timeout = 30')) {
  nobleDev = nobleDev.replace('async connect(timeout = 10)', 'async connect(timeout = 30)');
  fs.writeFileSync('/app/node_modules/ttlock-sdk-js/dist/scanner/noble/NobleDevice.js', nobleDev);
  console.log('Patched connect timeout: 10s -> 30s');
}

// Patch 4: Fix manager to expose unknown locks to API
let mgr = fs.readFileSync('/app/src/manager.js', 'utf8');
if (!mgr.includes('unknown lock also added to newLocks')) {
  mgr = mgr.replace(
    '    } else {\n      console.log(\"Discovered unknown lock:\", lock.toJSON());\n    }',
    '    } else {\n      // unknown lock also added to newLocks so API can see and pair it\n      console.log(\"Discovered unknown lock (adding to newLocks):\", lock.toJSON());\n      if (!this.newLocks.has(lock.getAddress())) {\n        this.newLocks.set(lock.getAddress(), lock);\n        listChanged = true;\n      }\n    }'
  );
  fs.writeFileSync('/app/src/manager.js', mgr);
  console.log('Patched manager to expose unknown locks');
}
"

cd /app
npm start
