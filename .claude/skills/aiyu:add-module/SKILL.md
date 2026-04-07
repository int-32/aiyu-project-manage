---
name: aiyu:add-module
description: >
  创建新的业务模块目录结构。当需要添加新模块、新建业务模块、
  创建新的 model/dao/service/router 结构、新增业务领域时自动使用。
  确保新模块与已有模块结构一致，包含完整的数据流定义和测试。
---

# 添加新业务模块

## 第一步：收集信息

用 AskUserQuestion 询问：
1. 模块名称（英文小写，如 payment, inventory, coupon）
2. 模块管理的核心实体
3. 负责的业务范围
4. 不负责的业务（容易混淆的边界）
5. 是否需要软删除
6. 核心实体是否有状态流转
   - 如果有：具体的状态列表和合法转换路径
   - 每个转换是否会触发跨模块副作用（如扣库存、发通知、发起支付）
7. 与哪些已有模块有依赖关系（本模块调用谁，谁调用本模块）

## 第二步：参考已有模块

阅读 app/ 下任意一个已有模块的完整结构，确保新模块在代码风格、
结构、命名上完全一致。特别注意：
- model.py 中 relationship 的写法
- dao.py 中继承 BaseDAO 的写法
- service.py 中副作用路由的写法（如果有）
- 测试文件的组织方式

## 第三步：创建模块文件

在 app/{module_name}/ 下创建：

### __init__.py — 职责声明

```python
"""
{模块名}模块。

负责：
- {具体职责}

不负责：
- {容易混淆的边界}

对外暴露：
- {Model}Service: 其他模块通过此 Service 调用本模块能力
"""
```

### model.py — 数据模型

- 继承 Base（需要软删除则额外继承 SoftDeleteMixin）
- 定义所有字段，写清 docstring
- 定义所有 relationship（与其他模块模型的关联）
- 在 docstring 中写明：
  - 生命周期（如果有状态流转）
  - 关联影响（其他实体的变化对本实体的影响）
- 如果有状态流转，定义：
  - VALID_TRANSITIONS：合法转换路径
  - TRANSITION_SIDE_EFFECTS：每个转换触发的副作用
  - can_transition_to() 方法
  - get_side_effects() 方法

### dao.py — 数据访问层

- 继承 BaseDAO[{Model}]
- 所有查询基于 self._base_query()
- 写 docstring 说明每个查询方法的用途

### service.py — 业务逻辑层

- 依赖注入：本模块 DAO + 需要调用的其他模块 Service
- 不直接使用 db.query()
- 不导入其他模块的 DAO
- 如果模型有状态流转：
  - 定义 _side_effect_handlers 字典
  - 实现 transition_status() 统一入口
  - 为每个副作用实现 _handle_xxx() 方法

### router.py — API 路由

- 定义 APIRouter，设置 prefix 和 tags
- 只调用 Service 层
- 使用 schemas.py 中的 Pydantic 模型做请求/响应验证

### schemas.py — Pydantic 模型

- 定义请求模型和响应模型
- 不暴露敏感字段
- 分页参数设上限（如 limit: int = Query(default=20, le=100)）

### CLAUDE.md — 模块专属规则

职责边界已在 __init__.py 中定义，不要在这里重复。
只写 __init__.py 不适合承载的信息。

```markdown
# {模块名}模块

职责边界见 __init__.py

## 数据流
{如有状态流转}
- 状态转换规则：model.py → VALID_TRANSITIONS
- 副作用定义：model.py → TRANSITION_SIDE_EFFECTS
- 副作用执行：service.py → _side_effect_handlers

## 容易犯的错误
（初始为空，随使用积累）
```

### tests/ — 测试

创建以下测试文件：

**test_dao.py**：
- 基本 CRUD 操作
- 软删除过滤（如果使用软删除）
- 模块专属的查询方法

**test_service.py**：
- 业务逻辑的正确性
- 参数校验和异常情况

**test_data_flow.py**（如果有状态流转）：
- 所有合法状态转换
- 典型的非法状态转换
- 每个副作用是否正确触发
- handler 完整性检查：

```python
def test_all_side_effects_have_handlers(self):
    for (from_s, to_s), effects in {Model}.TRANSITION_SIDE_EFFECTS.items():
        for effect in effects:
            assert effect in service._side_effect_handlers, (
                f"转换 {from_s}→{to_s} 的副作用 '{effect}' 缺少 handler"
            )
```

## 第四步：创建端到端流程测试（如需要）

如果新模块涉及跨模块的核心业务流程（如下单流程涉及用户、库存、支付），
在 tests/flows/ 下创建对应的流程测试文件。

流程测试覆盖：
- 正常路径（happy path）
- 主要异常路径
- 边界情况

## 第五步：更新工厂方法

在 tests/factories.py 中添加新模块的工厂方法：
- create_{model}() 函数
- 提供合理的默认值
- 接受 **overrides 覆盖参数

## 第六步：注册路由

在 app/main.py 中注册新模块的 router。

## 第七步：更新根 CLAUDE.md

如果有跨模块的边界决策（功能归属有歧义的），添加到根 CLAUDE.md 的模块边界表中。
不要把 __init__.py 中已经写明的职责再重复到根 CLAUDE.md。

## 第八步：验证

```bash
ruff check app/{module_name}/
pyright
pytest app/{module_name}/tests/ -v
python scripts/check_boundaries.py
```

如果创建了端到端流程测试：
```bash
pytest tests/flows/test_{module_name}_flow.py -v
```

全部通过后告诉用户模块创建完成。
