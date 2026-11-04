| Example | Guard | tuple_guards.pl | s2a2 types:implied_guard (unary) | Answers on random inputs |
| --- | --- | --- | --- | --- |
| trip | link(A,B) | deleted | kept | same(300) |
| trip_rail | link(A,B) | deleted | kept | same(300) |
| not_implied | link(B,A) | kept | kept | same(300) |
| relational_type | rt(A,C) | deleted | kept | same(300) |
| unary | person(A) | deleted | deleted | same(300) |
| no_binding | d(A) | kept | kept | same(300) |
| triple | ok(A,B,C) | deleted | kept | same(300) |
| not_implied, guard deleted by force | link(X,Y) | forced | - | differ([road(a,b),road(a,c),road(c,a),rail(b,b),rail(b,c),rail(c,a),rail(c,b)]) |
