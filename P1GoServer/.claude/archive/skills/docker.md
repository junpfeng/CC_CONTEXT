---
name: docker
description: Docker 容器化，Dockerfile 和 docker-compose 管理
---

# Docker 助手

当用户调用此 skill 时，帮助处理 Docker 相关工作。

## Dockerfile 模板

### Go 应用多阶段构建

```dockerfile
# 构建阶段
FROM golang:1.21-alpine AS builder

WORKDIR /app

# 安装依赖
RUN apk add --no-cache git ca-certificates tzdata

# 复制依赖文件
COPY go.mod go.sum ./
RUN go mod download

# 复制源码
COPY . .

# 构建
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/server ./cmd/server

# 运行阶段
FROM alpine:3.18

WORKDIR /app

# 安装基础工具
RUN apk --no-cache add ca-certificates tzdata

# 从构建阶段复制二进制文件
COPY --from=builder /app/server .
COPY --from=builder /app/configs ./configs

# 设置时区
ENV TZ=Asia/Shanghai

# 暴露端口
EXPOSE 8080

# 运行
CMD ["./server"]
```

### 带私有仓库的构建

```dockerfile
FROM golang:1.21-alpine AS builder

ARG GITHUB_TOKEN

WORKDIR /app

RUN apk add --no-cache git ca-certificates
RUN git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o /app/server ./cmd/server

FROM alpine:3.18
COPY --from=builder /app/server /app/server
CMD ["/app/server"]
```

## docker-compose 模板

```yaml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      - APP_ENV=development
      - DB_HOST=mysql
      - REDIS_HOST=redis
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_started
    volumes:
      - ./configs:/app/configs:ro
    networks:
      - app-network
    restart: unless-stopped

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    ports:
      - "3306:3306"
    volumes:
      - mysql-data:/var/lib/mysql
      - ./scripts/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data
    networks:
      - app-network

volumes:
  mysql-data:
  redis-data:

networks:
  app-network:
    driver: bridge
```

## 常用命令

```bash
# 构建镜像
docker build -t myapp:latest .

# 运行容器
docker run -d -p 8080:8080 --name myapp myapp:latest

# 查看日志
docker logs -f myapp

# 进入容器
docker exec -it myapp sh

# docker-compose 操作
docker-compose up -d        # 启动
docker-compose down         # 停止
docker-compose logs -f app  # 查看日志
docker-compose restart app  # 重启服务

# 清理
docker system prune -a      # 清理所有未使用的资源
```

## .dockerignore

```
# Git
.git
.gitignore

# IDE
.idea
.vscode
*.swp

# 测试和文档
*_test.go
docs/
README.md

# 本地配置
.env
.env.*
*.local.*

# 构建产物
bin/
dist/
*.exe
```

## 使用方式

- `/docker init` - 生成 Dockerfile
- `/docker compose` - 生成 docker-compose.yaml
- `/docker optimize` - 优化 Docker 构建
- `/docker debug` - 调试容器问题
