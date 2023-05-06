# teml

String Templates library for Lua, inspired by [Lust](https://github.com/weshoke/Lust) and [etlua](https://github.com/leafo/etlua).

This project started as a project that I will later abandoned, after several days I still working on it so I thought to continue this project.

## Usage

Require `teml` to retrieve the module (metatable), and then use it directly on strings. Any matched pattern `$(%S+)` or `${(.-)}` will be evaluated to value based on key table reference.
```lua
local teml = require("teml") -- The metatable contains `__call` metamethod, that's intended to alias `teml.eval`.

local foo = "foo"
local result_rad = math.rad(1)
print(teml[[Foo is $1 and result of `math.rad(1)` is ${result_rad}]]{ foo, result_rad=result_rad })
--- Above evaluated as:
--> Foo is foo and result of `math.rad(1)` is 0.017453292519943
```
You can also reference nested table or array by adding `.` (dot) separator.
```lua
local nested_table = {
    key1 = "buzz",
    key2 = { 123 }
}
local nested_array = {
    "bar",
    { key1 = "foo" }
}

print(teml[[`nested_table.key1` is $table.key1 and `nested_table.key2[1]` is $table.key2.1]]{ table=nested_table })
--> `nested_table.key1` is buzz and `nested_table.key[1]` is 123
print(teml[[`nested_array[1]` is $array.1 and `nested_array[2].key1` is $array.2.key1]]{ array=nested_array })
--> `nested_array[1]` is bar and `nested_array[2].key1` is foo
```

### Error handling

`teml` (or `teml.eval`) will always return second value if error has occured, return type of it is `string?, string?`.

Here's an example of how teml return an error.
```lua
local result, err = teml[[error -> ${ }]]{1}

print(result, err)
--- Above will print as:
--> nil  line 1: empty variable name.
```

An exact fix of it is to not let variable reference empty.
```lua
local result, err = teml[[fix -> ${1}]]{1}

print(result, err)
--- Above will print as:
--> fix -> 1  nil
```

### Conditions

`@if` statement takes comparison expression and applies template if expression evaluates to true. Adding `@else` proceeded with block will act as alternative template inside the block. Caveats that comparison expression uses `load` or `loadstring` for evaluating the expression.
```lua
-- Conditional `@if` checks if comparison expression evaluate to true, if true proceed to apply template inside block.
-- You can also use template inside the comparison expression.
-- `@if(&exist(x))` checks if `x` is exist.
local template = teml[[@if(&exist(x)){Hello}]]

template{ x=true }   --> "Hello"
template{ x=false }  --> "Hello"
template{ }          --> ""
```
```lua
-- Using `@else` and inline templates
local template = teml[[@if(&exist(y)){Y is exist}@else{Y is not exist}]]

template{ y=true }   --> "Y is exist"
template{ y=1234 }   --> "Y is exist"
template{ x="foo" }  --> "Y is not exist"
```
```lua
-- Using comparison operator (equal)
local template = teml[[@if($num == 123){num is 123}]]

template{ num=123 }  --> "num is 123"
template{ num=321 }  --> ""
template{ }          --> ""
```
```lua
-- Using comparison operator (more, less, logical operator)
local template = teml[[@if($num > 99 and $num < 1001){num is above 99 and below 1001}]]

template{ num=100 }     --> "num is above 99 and below 1001"
template{ num=1000 }    --> "num is above 99 and below 1001"
template{ num=0 }       --> ""
template{ }             --> ""
```

### Loops and Iterator

teml support table and numeric iteration using `@for` keyword. If you are familiar with C++ especially using iterator in range-for loop, then `@for` also implement that kind of syntax. `@for` takes `<variable> : <iterator>`, `<variable>` meams one variable or more that'll supply the return of iterator, while `<iterator>` itself is either range or table name.
```lua
-- Example of numeric iteration.
--- `S..E..I` where `S` is start of iter number, `E` is end of iter number and `I` is increment of iter number.
local template = teml[[@for(i : 1..3..1){i is ${i}, }]]

template{}    --> "i is 1, i is 2, i is 3, "
```
```lua
-- Example of table iteration.
--- Table iteration takes up to variable, `i`ndex/`k`ey and `v`alue.
local template = teml[[@for(i,v : array){i is ${i}, v is ${v}, }]]

template{ array={ 3,2,1 } }  --> "i is 1, v is 3, i is 2, v is 2, i is 3, v is 1, "
```

### Parameter Expansion

Parameter Expansion is like Bash's or Zsh's Parameter Expansion, currently only `${name:-word}` and `${name:+word}` are implemented. Parameter Expansion is useful if you don't want `nil` when referencing a non-existent variable.
```lua
-- Replacement Parameter
local template = teml[[${something_nil:-} doesn't evaluate as `${null:-nil}`]]

template{ }                            --> " doesn't evaluate as `nil`"
template{ something_nil="something" }  --> "something doesn't evaluate as `nil`"
template{ null="null" }                --> " doesn't evaluate as `null`"
template{ something_nil="something"
        , null="null" }                --> "something doesn't evaluate as `null`"
```

### Functions

Functions are straight forward, you call it and it'll return. Standard functions library are only `string`, especially `sub`, `rep`, `reverse`, `upper`, `lower` and `byte` and one additional `exist` function, it is used to check an existence of table key (variable).
```lua
-- Example of using function
--- Function must be separated with a comma without space surrounding it.
local template = teml[[+&string.rep(-,5)+]]

template{ }    --> "+-----+"
```
```lua
-- Example of using function with template
local template = teml[[&string.reverse($1)]]

template{ "Some words" }    --> "sdrow emoS"
```
