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

# Runtime SDK patches
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

// Patch 2: Default lockType for devices without manufacturerData
let btDev = fs.readFileSync('/app/node_modules/ttlock-sdk-js/dist/device/TTBluetoothDevice.js', 'utf8');
if (!btDev.includes('LOCK_TYPE_V3 fallback')) {
  btDev = btDev.replace(
    'if (this.device.manufacturerData.length >= 15) {\n                this.parseManufacturerData(this.device.manufacturerData);\n            }',
    'if (this.device.manufacturerData.length >= 15) {\n                this.parseManufacturerData(this.device.manufacturerData);\n            } else {\n                // LOCK_TYPE_V3 fallback for locks advertising UUID without manufacturerData\n                const Lock_fb = require(\"../constant/Lock\");\n                if (this.lockType === Lock_fb.LockType.UNKNOWN) {\n                    this.lockType = Lock_fb.LockType.LOCK_TYPE_V3;\n                    this.protocolType = 5;\n                    this.protocolVersion = 3;\n                    console.log(\"Applied LOCK_TYPE_V3 fallback for device: \" + this.name);\n                }\n            }'
  );
  fs.writeFileSync('/app/node_modules/ttlock-sdk-js/dist/device/TTBluetoothDevice.js', btDev);
  console.log('Patched lockType fallback');
}
"

cd /app
npm start
