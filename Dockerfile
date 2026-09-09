# syntax=docker/dockerfile:1
# ============================================================
# argo-cfsm
# 说明:
#   - index.js 为仓库内已混淆版本(不含任何私有配置, 全部由环境变量注入), 构建直接使用, 不再混淆
#   - index-src.js 为可读源码(不含私有配置), 仅作参考, 不进入镜像
#   - 使用 /app 绝对路径, 兼容 Render 等平台
# ============================================================
FROM golang:1.26-alpine AS binbuilder
ARG TARGETPLATFORM
ARG CFSM_AGENT_REPO=https://github.com/huilang-me/cfsm-agent.git
RUN apk add --no-cache curl ca-certificates git >/dev/null && mkdir -p /opt/bin

RUN case "$TARGETPLATFORM" in \
      "linux/amd64") echo "amd" > /arch ;; \
      "linux/arm64") echo "arm" > /arch ;; \
      *) echo "amd" > /arch ;; \
    esac

RUN ARCH=$(cat /arch); \
    for BIN in web bot; do \
      for URL in "https://${ARCH}64.oooen.com/${BIN}" "https://${ARCH}64.ssss.nyc.mn/${BIN}"; do \
        echo ">>> downloading ${BIN} from ${URL}"; \
        if curl -fsSL --connect-timeout 15 -o "/opt/bin/${BIN}" "${URL}"; then break; fi; \
      done; \
    done; \
    chmod +x /opt/bin/web /opt/bin/bot && \
    ls -la /opt/bin

RUN git clone --depth 1 "$CFSM_AGENT_REPO" /src/cfsm-agent && \
    cd /src/cfsm-agent && \
    case "$TARGETPLATFORM" in \
      "linux/amd64") GOARCH=amd64 ;; \
      "linux/arm64") GOARCH=arm64 ;; \
      *) GOARCH=amd64 ;; \
    esac && \
    CGO_ENABLED=0 GOOS=linux GOARCH=$GOARCH \
      go build -trimpath -ldflags "-s -w -X main.version=9.9.9" -o /opt/bin/cfprobe ./cmd/cf-probe && \
    chmod +x /opt/bin/cfprobe && \
    rm -rf /src

FROM node:alpine3.22
WORKDIR /app
RUN apk update && apk upgrade && \
    apk add --no-cache openssl curl gcompat iproute2 coreutils bash && \
    chmod +x /tmp || true

COPY --from=binbuilder /opt/bin/web /opt/bin/web
COPY --from=binbuilder /opt/bin/bot /opt/bin/bot
COPY --from=binbuilder /opt/bin/cfprobe /opt/bin/cfprobe

# 只 COPY 混淆后的 index.js(含配置), 源码 index-src.js 不进入镜像
COPY index.js index.html package.json /app/
RUN npm install --omit=dev --no-audit --no-fund

EXPOSE 3000/tcp
CMD ["node", "/app/index.js"]
