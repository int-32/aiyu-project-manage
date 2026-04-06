# 项目初始化工具包

一套 Claude Code Skills，用于初始化和维护 Python FastAPI 项目。
确保项目结构对 AI 友好，让 Claude Code 能自主、准确地完成开发任务。

## 设计理念

- **按模块纵切**：每个业务模块自包含，Claude 只需加载当前模块的上下文
- **代码即文档**：关联关系写在 ORM relationship 中，状态规则写在 Model 常量中，业务流程写在端到端测试中
- **自动护栏**：软删除过滤由 BaseDAO 自动处理，模块边界由脚本检查，数据流完整性由测试验证
- **分级加载 CLAUDE.md**：全局规则放根目录，模块规则放模块目录，互不干扰

## 包含内容

```
.claude/skills/
├── init-project/SKILL.md      # 初始化新项目
├── add-module/SKILL.md        # 添加新业务模块
└── entropy-review/SKILL.md    # 定期熵减审计

scripts/
└── check_boundaries.py        # 模块边界检查脚本
```

## 快速开始

### 1. 安装

```bash
bash install.sh
```

自动完成：安装 4 个 Skills、配置 Claude Code 提交提醒 hook、复制脚本模板、检查依赖。

### 2. 安装 LSP 插件（在 Claude Code 中）

```
/plugin install pyright-lsp@claude-plugins-official
```

### 3. 使用

```
/init-project          # 新项目初始化
/migrate-project       # 旧项目迁移
/add-module            # 添加业务模块
/entropy-review        # 熵减审计
```

### 卸载

```bash
bash uninstall.sh
```

只清理工具包本身（Skills、hook、模板），不影响已创建的项目代码。

## 生成的项目结构

```
project/
├── app/
│   ├── common/                    # 公共基础设施
│   │   ├── base_model.py          # Base + SoftDeleteMixin
│   │   ├── base_dao.py            # BaseDAO（自动软删除过滤）
│   │   ├── base_service.py        # BaseService
│   │   └── exceptions.py          # 公共异常类
│   └── {module}/                  # 业务模块（自包含）
│       ├── __init__.py            # 职责声明
│       ├── model.py               # 模型 + relationship + 状态规则 + 副作用定义
│       ├── dao.py                 # 数据访问（继承 BaseDAO）
│       ├── service.py             # 业务逻辑 + 副作用执行
│       ├── router.py              # API 路由
│       ├── schemas.py             # Pydantic 模型
│       ├── CLAUDE.md              # 数据流 + 容易犯的错误
│       └── tests/
│           ├── test_dao.py        # DAO 测试
│           ├── test_service.py    # Service 测试
│           └── test_data_flow.py  # 状态转换 + 副作用测试
├── tests/
│   ├── conftest.py                # 全局 fixtures
│   ├── factories.py               # 测试数据工厂
│   └── flows/                     # 端到端业务流程测试
│       └── test_{xxx}_flow.py
├── scripts/
│   └── check_boundaries.py
├── CLAUDE.md                      # 全局规则 + 边界歧义决策
├── ruff.toml
├── pyrightconfig.json
└── pytest.ini
```

## 核心机制

### 数据关联：通过 ORM relationship 显式定义
Claude 读 model.py 就能看到所有表关联，不需要从业务代码推理。

### 模块边界：每个信息只在一个地方定义
- 模块职责（负责/不负责/对外暴露）→ 只在 `__init__.py` 中定义
- 跨模块边界歧义决策 → 只在根 `CLAUDE.md` 边界表中记录
- 数据流和容易犯的错误 → 只在模块 `CLAUDE.md` 中记录

### 软删除：BaseDAO._base_query() 自动处理
继承 SoftDeleteMixin 的模型，查询时自动排除已删除记录，消除遗漏风险。

### 状态流转：Model 定义规则，Service 执行副作用
- VALID_TRANSITIONS：哪些转换合法
- TRANSITION_SIDE_EFFECTS：每个转换触发什么副作用
- _side_effect_handlers：副作用怎么执行

### 业务流程：端到端测试即文档
tests/flows/ 中的测试文件就是业务流程的可执行文档，始终与代码同步。

### 架构护栏：脚本自动检查
check_boundaries.py 检测跨模块 DAO 导入、Service 层直接查数据库等违规。

### CLAUDE.md 分级加载
- ~/.claude/CLAUDE.md：个人偏好
- 根目录 CLAUDE.md：全局架构规则 + 边界歧义决策
- 模块目录 CLAUDE.md：数据流 + 容易犯的错误（仅在该模块工作时加载）

## 日常使用

添加新模块：`/add-module`
熵减审计（建议每两周）：`/entropy-review`

## 旧项目迁移

1. 安装工具链（ruff, pyright, pytest, LSP 插件）
2. 创建 app/common/ 基础设施
3. 选一个模块做试点迁移
4. 试点成功后用 /add-module 逐步迁移其他模块
5. 在根 CLAUDE.md 中标注迁移状态
