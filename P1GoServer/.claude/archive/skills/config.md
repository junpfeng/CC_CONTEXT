---
name: config
description: 配置管理，处理环境变量和配置文件
---

# 配置管理助手

当用户调用此 skill 时，帮助处理项目配置。

## 配置最佳实践

### 1. 配置文件结构

```yaml
# config.yaml
app:
  name: my-service
  env: development
  port: 8080

database:
  host: localhost
  port: 3306
  name: mydb
  user: root
  password: ${DB_PASSWORD}  # 从环境变量读取

redis:
  host: localhost
  port: 6379

log:
  level: info
  format: json
```

### 2. Go 配置结构

```go
type Config struct {
    App      AppConfig      `mapstructure:"app"`
    Database DatabaseConfig `mapstructure:"database"`
    Redis    RedisConfig    `mapstructure:"redis"`
    Log      LogConfig      `mapstructure:"log"`
}

type AppConfig struct {
    Name string `mapstructure:"name"`
    Env  string `mapstructure:"env"`
    Port int    `mapstructure:"port"`
}

type DatabaseConfig struct {
    Host     string `mapstructure:"host"`
    Port     int    `mapstructure:"port"`
    Name     string `mapstructure:"name"`
    User     string `mapstructure:"user"`
    Password string `mapstructure:"password"`
}
```

### 3. 使用 Viper 加载配置

```go
func LoadConfig(path string) (*Config, error) {
    viper.SetConfigFile(path)
    viper.AutomaticEnv()

    // 环境变量替换
    viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

    if err := viper.ReadInConfig(); err != nil {
        return nil, err
    }

    var config Config
    if err := viper.Unmarshal(&config); err != nil {
        return nil, err
    }

    return &config, nil
}
```

### 4. 多环境配置

```
configs/
├── config.yaml           # 基础配置
├── config.development.yaml
├── config.staging.yaml
└── config.production.yaml
```

```go
// 根据环境加载配置
env := os.Getenv("APP_ENV")
if env == "" {
    env = "development"
}
viper.SetConfigFile(fmt.Sprintf("configs/config.%s.yaml", env))
```

### 5. 敏感信息处理

```bash
# .env 文件（不提交到 Git）
DB_PASSWORD=secret
JWT_SECRET=your-secret-key
API_KEY=xxx

# .env.example（提交到 Git）
DB_PASSWORD=
JWT_SECRET=
API_KEY=
```

```go
// 使用 godotenv 加载
import "github.com/joho/godotenv"

func init() {
    godotenv.Load() // 加载 .env 文件
}
```

### 6. 配置验证

```go
func (c *Config) Validate() error {
    if c.App.Port <= 0 || c.App.Port > 65535 {
        return errors.New("invalid port number")
    }
    if c.Database.Host == "" {
        return errors.New("database host is required")
    }
    return nil
}
```

## .gitignore 配置

```gitignore
# 环境配置
.env
.env.local
.env.*.local
*.pem
*.key

# 本地配置
config.local.yaml
config.development.yaml

# 敏感文件
credentials.json
secrets/
```

## 使用方式

- `/config show` - 显示当前配置结构
- `/config validate` - 验证配置文件
- `/config env` - 管理环境变量
- `/config template` - 生成配置模板
