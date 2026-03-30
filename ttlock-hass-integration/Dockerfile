ARG BUILD_FROM
FROM $BUILD_FROM

ENV LANG C.UTF-8

RUN apk update && apk add --no-cache nodejs npm python3 make g++ libcap bluez bluez-dev eudev-dev linux-headers
RUN setcap cap_net_raw+eip $(readlink -f $(which node))

WORKDIR /

COPY start.sh /app/start.sh
COPY addon /app
RUN rm -rf /app/node_modules

RUN cd /app && npm i && sed -i 's/exports.TTLockUUIDs = ["1910", "00001910-0000-1000-8000-00805f9b34fb"]/exports.TTLockUUIDs = ["1910", "00001910-0000-1000-8000-00805f9b34fb", "021a9004-0382-4aea-bff4-6b3f1c5adfb4"]/' /app/node_modules/ttlock-sdk-js/dist/scanner/BluetoothLeService.js

ENTRYPOINT ["/app/start.sh"]

LABEL io.hass.version="0.4.11" io.hass.type="addon" io.hass.arch="aarch64|amd64"
