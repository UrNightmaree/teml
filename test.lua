local template = teml[[${something_nil:-} doesn't evaluate as `${null:-nil}`]]

print(template{ })                            --> " doesn't evaluate as `nil`"
print(template{ something_nil="something" })  --> "something doesn't evaluate as `nil`"
print(template{ null="null" })                --> " doesn't evaluate as `null`"
print(template{ something_nil="something"
              , null="null" })                --> "something doesn't evaluate as `null`"

