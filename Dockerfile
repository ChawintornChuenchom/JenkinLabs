FROM node:20-alpine
WORKDIR /app
# ดึง security patch ล่าสุดของแพ็กเกจระบบ Alpine เอง (libssl3/libcrypto3 ฯลฯ) ก่อน
RUN apk upgrade --no-cache
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && \
    # npm CLI เองมี node_modules ของมันเองฝังมากับ base image (pacote, tar, glob, minimatch,
    # sigstore ฯลฯ) ซึ่งมี CVE จำนวนมากที่ Trivy เจอ แต่ runtime ของแอปเราไม่เคยเรียกใช้ npm เลย
    # (แค่ `node src/server.js`) ลบทิ้งออกจาก image ที่จะรันจริงได้เลย ปลอดภัยกว่าและ scan ผ่านง่ายขึ้น
    rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
COPY src ./src
EXPOSE 8080
CMD ["node", "src/server.js"]
