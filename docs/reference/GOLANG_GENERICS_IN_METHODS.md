# Go 语言中结构体方法使用泛型

## 规则说明

### ✅ 允许的方式

#### 1. 泛型结构体的方法可以使用结构体的类型参数

```go
// 泛型结构体
type Container[T any] struct {
    items []T
}

// 方法可以使用结构体的类型参数 T
func (c *Container[T]) Add(item T) {
    c.items = append(c.items, item)
}

func (c *Container[T]) Get(index int) T {
    return c.items[index]
}

// 使用示例
func Example() {
    intContainer := &Container[int]{items: []int{1, 2, 3}}
    intContainer.Add(4)
    
    strContainer := &Container[string]{items: []string{"a", "b"}}
    strContainer.Add("c")
}
```

#### 2. 方法内部调用泛型函数

```go
type MyStruct struct {
    value int
}

// 方法本身不是泛型的，但可以调用泛型函数
func (m *MyStruct) Process[T any](data T) T {
    return processGeneric(data)  // 调用泛型函数
}

// 泛型函数
func processGeneric[T any](data T) T {
    // 处理逻辑
    return data
}
```

#### 3. 方法返回泛型类型（通过接口约束）

```go
type Processor struct {
    // ...
}

// 方法返回接口类型，实际可以是不同的泛型实现
func (p *Processor) GetContainer() ContainerInterface {
    // 返回实现了 ContainerInterface 的具体类型
}

type ContainerInterface interface {
    Get(index int) any
}
```

### ❌ 不允许的方式

#### 1. 方法本身不能有类型参数

```go
type MyStruct struct {
    value int
}

// ❌ 错误：方法不能有类型参数
func (m *MyStruct) Process[T any](data T) T {
    return data
}
```

**错误信息**：`method must have no type parameters`

#### 2. 非泛型结构体的方法不能使用泛型类型参数

```go
type MyStruct struct {
    value int
}

// ❌ 错误：非泛型结构体的方法不能使用类型参数
func (m *MyStruct) Get[T any]() T {
    // ...
}
```

## 实际应用示例

### 示例 1：泛型容器

```go
package main

import "fmt"

// 泛型结构体
type Stack[T any] struct {
    items []T
}

// 方法使用结构体的类型参数
func (s *Stack[T]) Push(item T) {
    s.items = append(s.items, item)
}

func (s *Stack[T]) Pop() (T, bool) {
    if len(s.items) == 0 {
        var zero T
        return zero, false
    }
    item := s.items[len(s.items)-1]
    s.items = s.items[:len(s.items)-1]
    return item, true
}

func (s *Stack[T]) IsEmpty() bool {
    return len(s.items) == 0
}

func main() {
    // 整数栈
    intStack := &Stack[int]{}
    intStack.Push(1)
    intStack.Push(2)
    val, _ := intStack.Pop()
    fmt.Println(val) // 输出: 2
    
    // 字符串栈
    strStack := &Stack[string]{}
    strStack.Push("hello")
    strStack.Push("world")
    str, _ := strStack.Pop()
    fmt.Println(str) // 输出: world
}
```

### 示例 2：方法调用泛型辅助函数

```go
package main

import "fmt"

type DataProcessor struct {
    name string
}

// 方法本身不是泛型的，但调用泛型函数
func (dp *DataProcessor) ProcessInt(value int) int {
    return processValue(value)
}

func (dp *DataProcessor) ProcessString(value string) string {
    return processValue(value)
}

// 泛型辅助函数
func processValue[T any](value T) T {
    // 处理逻辑
    return value
}

func main() {
    dp := &DataProcessor{name: "processor"}
    result := dp.ProcessInt(42)
    fmt.Println(result)
}
```

### 示例 3：使用接口约束

```go
package main

import "fmt"

// 约束接口
type Numeric interface {
    int | int32 | int64 | float32 | float64
}

// 泛型结构体
type Calculator[T Numeric] struct {
    value T
}

// 方法使用结构体的类型参数
func (c *Calculator[T]) Add(other T) T {
    return c.value + other
}

func (c *Calculator[T]) Multiply(other T) T {
    return c.value * other
}

func main() {
    intCalc := &Calculator[int]{value: 10}
    fmt.Println(intCalc.Add(5))        // 15
    fmt.Println(intCalc.Multiply(2))  // 20
    
    floatCalc := &Calculator[float64]{value: 10.5}
    fmt.Println(floatCalc.Add(5.5))        // 16.0
    fmt.Println(floatCalc.Multiply(2.0))   // 21.0
}
```

### 示例 4：在你的代码中的应用

基于你的 `ObjectFuncComp` 结构，可以这样使用泛型：

```go
// 泛型查找方法（通过辅助函数实现）
func FindFunc[T IObjFunc](funcList []IObjFunc) (T, bool) {
    for _, f := range funcList {
        if typed, ok := f.(T); ok {
            return typed, true
        }
    }
    var zero T
    return zero, false
}

// 在方法中使用
func (o *ObjectFuncComp) GetFunc(funcType config.CfgConstObjFunction) IObjFunc {
    for _, f := range o.FuncList {
        if f.Type() == funcType {
            return f
        }
    }
    return nil
}

// 类型安全的获取方法（使用泛型辅助函数）
func (o *ObjectFuncComp) GetFuncTyped[T IObjFunc]() (T, bool) {
    return FindFunc[T](o.FuncList)
}

// 使用示例
func Example() {
    comp := &ObjectFuncComp{
        FuncList: []IObjFunc{
            &ObjFuncSoilContainer{SoilId: 1, SoilNum: 10},
            &ObjFuncSeedContainer{SeedId: 2},
        },
    }
    
    // 类型安全的获取
    soilFunc, ok := comp.GetFuncTyped[*ObjFuncSoilContainer]()
    if ok {
        fmt.Println(soilFunc.SoilId)  // 1
    }
}
```

## 总结

1. **方法本身不能有类型参数**，但泛型结构体的方法可以使用结构体的类型参数
2. **方法内部可以调用泛型函数**来实现泛型功能
3. **使用接口约束**可以在方法中实现类型安全的泛型操作
4. **Go 1.18+** 才支持泛型，确保你的 Go 版本 >= 1.18

## 检查 Go 版本

```bash
go version
```

如果版本 < 1.18，需要升级：

```bash
# Ubuntu
sudo apt update
sudo apt install golang-go

# 或从官网下载最新版本
# https://go.dev/dl/
```
