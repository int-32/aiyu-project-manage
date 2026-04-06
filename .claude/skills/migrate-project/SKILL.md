---
name: migrate-project
description: >
  将已有的 Python FastAPI 项目迁移到标准化架构。
  逐步进行，不停业务，不破坏现有功能。
  当用户说"迁移项目"、"重构项目结构"、"改造旧项目"时使用。
disable-model-invocation: true
---

# 已有项目迁移 Skill

本 Skill 将已有项目逐步迁移到标准化架构。
核心原则：每一步都可独立验证，做完一步再做下一步，任何一步失败都可回滚。

## 阶段零：评估现状

### 步骤 0.1：扫描项目

分析当前项目，生成评估报告到 docs/migration/assessment.md：

```bash
# 目录结构
find . -type f -name "*.py" | head -100

# ORM 模型
rg "class.*Base\)" --type py -l
rg "Column\(|relationship\(" --type py -l

# 数据库表数量
rg "__tablename__" --type py

# 现有测试
find . -name "test_*.py" -o -name "*_test.py" | head -50

# 现有 lint 配置
ls -la ruff.toml pyproject.toml .flake8 .pylintrc pyrightconfig.json 2>/dev/null

# 路由定义
rg "APIRouter\(\)|@router\.|@app\." --type py -l
```

报告内容：
1. 当前目录结构概览
2. 数据库表清单（表名 + 模型文件位置）
3. 现有的模块划分方式（按技术层横切 / 按业务纵切 / 混合 / 无结构）
4. 现有的测试和 lint 基础
5. ORM 中 relationship 的定义完整度
6. 跨表查询的方式（ORM relationship / 手动 JOIN / 混合）

### 步骤 0.2：确认迁移范围

用 AskUserQuestion 询问用户：
1. 评估报告是否准确，有无需要补充的信息
2. 哪些模块是当前最活跃、Claude 最常改的（优先迁移这些）
3. 有没有不能动的代码（如第三方集成、遗留接口）
4. 项目是否有 CI/CD，迁移后是否需要保证 CI 通过

## 阶段一：搭建基础设施（不改动任何现有代码）

### 步骤 1.1：安装工具链

检查并安装缺失的工具：

```bash
# 检查已有工具
pip show ruff pyright pytest 2>/dev/null

# 安装缺失的
pip install ruff pyright pytest pytest-asyncio
```

如果项目已有 lint/test 配置，保留现有配置，不覆盖。
如果没有，创建新配置：

ruff.toml：
```toml
target-version = "py311"
line-length = 120

[lint]
select = ["E", "F", "I", "B", "SIM", "T20", "S", "RET", "ARG"]

[lint.per-file-ignores]
"tests/**" = ["T20", "S101", "ARG"]
"**/test_*.py" = ["T20", "S101", "ARG"]
```

pyrightconfig.json：
```json
{
  "typeCheckingMode": "basic",
  "pythonVersion": "3.11",
  "reportMissingTypeStubs": false,
  "reportUnknownMemberType": false
}
```

pytest.ini（如果不存在）：
```ini
[pytest]
testpaths = tests app
asyncio_mode = auto
addopts = -v --tb=short
```

### 步骤 1.2：创建公共基础设施

在 app/common/ 下创建：
- base_model.py（Base + SoftDeleteMixin）
- base_dao.py（BaseDAO，带 _base_query 自动软删除过滤）
- base_service.py（BaseService）
- exceptions.py（公共异常类）

严格按照 init-project skill 中的模板创建。
不改动任何现有代码，只添加新文件。

### 步骤 1.3：创建工具脚本和 Skills

- scripts/check_boundaries.py（模块边界检查）
- scripts/pre-commit（git pre-commit hook）
- .claude/skills/add-module/SKILL.md
- .claude/skills/entropy-review/SKILL.md
- .claude/settings.json（Claude Code 提交前提醒 hook）
- docs/migration/（迁移文档目录）

安装 pre-commit hook：
```bash
cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

### 步骤 1.4：创建根 CLAUDE.md

```markdown
# 项目名称
项目描述

## 命令
- ruff check . --fix
- pyright
- pytest
- python scripts/check_boundaries.py

## 当前状态
项目正在从旧结构迁移到按模块纵切的标准化架构。
- app/common/ 下是公共基础设施
- 已迁移的模块在 app/ 下以独立目录存在
- 未迁移的代码仍在旧位置

## 重要规则
- 不要主动重构未迁移的代码
- 对未迁移代码的功能修改在旧位置进行
- 迁移工作与功能开发分开，不在同一个会话中混做
- 需要创建新的业务模块时，必须使用 /add-module，不要手动创建模块目录结构
- 定期运行 /entropy-review 进行项目健康度审计

## 架构规范
（迁移完成后的目标架构，同 init-project 中的描述）

## 迁移状态
| 模块 | 状态 | 备注 |
|------|------|------|
| common | ✅ 完成 | 公共基础设施 |
| （其他模块随迁移进度更新） | | |

## 模块边界

每个模块的职责边界定义在该模块的 __init__.py 中，不要在其他地方重复。
以下决策表只记录有歧义的、讨论后做出的跨模块边界决策：

| 功能 | 归属模块 | 原因 |
|------|---------|------|
| （随迁移推进补充） | | |
```

### 步骤 1.5：验证

```bash
ruff check app/common/
pyright app/common/
```

确认基础设施代码本身没有问题。
现有代码不需要通过这些检查（还没迁移）。

提交：
```bash
git add -A
git commit -m "feat: add common infrastructure for migration"
```

告诉用户阶段一完成，让用户确认后再继续。

## 阶段二：迁移试点模块

### 步骤 2.1：选择试点模块

根据步骤 0.2 的信息选择试点模块。
选择标准：
- 业务逻辑中等复杂
- 跨模块交互不太多
- 用户最熟悉（方便审查）

### 步骤 2.2：分析试点模块

```bash
# 搜索该模块相关的所有文件
rg "class {ModelName}" --type py -l
rg "import.*{ModelName}" --type py -l
rg "{table_name}" --type py -l
rg "JOIN.*{table_name}" --type py
```

生成分析报告到 docs/migration/{module}_analysis.md：
1. 涉及的文件清单
2. 涉及的数据库表和 ORM 模型位置
3. 表间关联关系（从 relationship 定义和代码中的 JOIN 推断）
4. 状态流转（如果有）
5. 每个状态转换触发的跨模块副作用
6. 该模块依赖的其他模块
7. 其他模块依赖该模块的地方
8. 现有的直接 db.query() 调用位置

**重要**：告诉用户分析结果，让用户审查确认后再继续。
如果用户指出分析有误，修正分析报告后再进行迁移。

### 步骤 2.3：创建新模块

在 app/{module}/ 下创建完整结构：

1. __init__.py — 职责声明（负责/不负责/对外暴露），这是模块边界的唯一定义位置
2. model.py：
   - 从旧位置的模型定义迁移
   - 改为继承 app/common/base_model.py 的 Base
   - 需要软删除的加上 SoftDeleteMixin
   - 补全所有 relationship 定义
   - 如有状态流转，添加 VALID_TRANSITIONS 和 TRANSITION_SIDE_EFFECTS
   - docstring 写明生命周期和关联影响
3. dao.py — 继承 BaseDAO，迁移所有相关查询
4. service.py — 迁移业务逻辑，如有副作用添加 _side_effect_handlers
5. router.py — 迁移路由
6. schemas.py — Pydantic 模型
7. CLAUDE.md — 只写数据流和容易犯的错误，不重复 __init__.py 中的职责声明

**先创建新文件，不删除旧文件。新旧代码短暂共存。**

### 步骤 2.4：创建测试

在 app/{module}/tests/ 下创建：
- test_dao.py：基本 CRUD + 软删除过滤
- test_service.py：业务逻辑
- test_data_flow.py（如有状态流转）：状态转换 + 副作用 + handler 完整性

在 tests/flows/ 下创建（如有跨模块流程）：
- test_{module}_flow.py：端到端流程测试

更新 tests/factories.py（如不存在则创建）。
更新 tests/conftest.py（如不存在则创建）。

运行测试确认通过：
```bash
pytest app/{module}/tests/ -v
```

### 步骤 2.5：切换引用

```bash
# 搜索所有引用旧路径的地方
rg "from.*旧路径.*import.*{ModelName}" --type py
rg "import.*旧路径.*{ModelName}" --type py
```

逐个替换为新路径。每替换一个文件：
```bash
pyright {被修改的文件}
```

全部替换完后：
```bash
pytest
python scripts/check_boundaries.py
```

全部通过后删除旧文件。

### 步骤 2.6：提交并更新状态

```bash
git add -A
git commit -m "refactor: migrate {module} to modular architecture"
```

更新根 CLAUDE.md 的迁移状态表。

告诉用户试点模块迁移完成，让用户确认质量后再继续。

## 阶段三：批量迁移剩余模块

### 步骤 3.1：确定迁移顺序

根据步骤 0.1 的分析，按依赖关系从底层往上排序：
- 第一批：被依赖最多的基础模块
- 第二批：核心业务模块
- 第三批：辅助模块
- 最后：边缘模块（日志、配置、统计等）

将迁移顺序写入 docs/migration/plan.md。

### 步骤 3.2：逐模块迁移

对每个模块重复阶段二的步骤 2.2 ~ 2.6。
每个模块一个独立的会话，不要在一个会话里迁移多个模块。

每个模块迁移完后的检查清单：
- [ ] analysis.md 中的表关系经用户确认
- [ ] __init__.py 包含完整的职责声明（负责/不负责/对外暴露）
- [ ] model.py 的 relationship 完整
- [ ] 有状态流转的模型定义了 VALID_TRANSITIONS 和 TRANSITION_SIDE_EFFECTS
- [ ] dao.py 都走 _base_query()
- [ ] service.py 无直接数据库操作
- [ ] 副作用 handler 与 Model 定义同步
- [ ] 跨模块依赖走 Service
- [ ] 模块 CLAUDE.md 只含数据流和容易犯的错误（不重复 __init__.py 的职责）
- [ ] 单元测试通过
- [ ] 数据流测试通过（如有）
- [ ] 端到端流程测试通过（如有）
- [ ] check_boundaries.py 通过
- [ ] pyright 通过
- [ ] ruff check 通过
- [ ] 旧文件已清理
- [ ] 根 CLAUDE.md 迁移状态已更新

### 步骤 3.3：迁移完成后清理

所有模块迁移完成后：

1. 删除 CLAUDE.md 中的"迁移状态"段落和"当前状态"段落
2. 删除"不要主动重构未迁移的代码"规则
3. 运行一次完整的熵减审计：/entropy-review
4. 清理 docs/migration/ 中的分析报告（可保留作历史参考）

最终提交：
```bash
git add -A
git commit -m "refactor: complete migration to modular architecture"
```

## 应急回滚

迁移过程中如果发现严重问题：

单个模块回滚：
```bash
git revert HEAD  # 撤销最近的迁移提交
```

整体回滚到迁移前：
```bash
git log --oneline  # 找到迁移前的 commit
git reset --hard {commit_hash}
```

每个模块独立提交就是为了保证可以单独回滚。
