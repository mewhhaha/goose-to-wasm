(module
 (type $0 (func (param i32)))
 (type $1 (func))
 (type $2 (func (param i64)))
 (type $3 (func (result i64)))
 (type $4 (func (param i32) (result i32)))
 (type $5 (func (param i32 i32)))
 (type $6 (func (param f64)))
 (type $7 (func (param f32)))
 (type $8 (func (param i32 i32 i32)))
 (type $9 (func (param i32 i32 i32 f64 f64) (result i64)))
 (type $10 (func (param f64) (result i64)))
 (type $11 (func (param i32 i32 i32 i32 f64 f64) (result i64)))
 (import "goose" "write" (func $fimport$0 (param i32 i32)))
 (import "goose" "print_i64" (func $fimport$1 (param i64)))
 (import "goose" "print_u64" (func $fimport$2 (param i64)))
 (import "goose" "print_f64" (func $fimport$3 (param f64)))
 (import "goose" "print_f32" (func $fimport$4 (param f32)))
 (import "goose" "print_bool" (func $fimport$5 (param i32)))
 (import "goose" "newline" (func $fimport$6))
 (import "goose" "abort" (func $fimport$7 (param i32 i32 i32)))
 (import "goose" "exit" (func $fimport$8 (param i32)))
 (import "env" "bench_input" (func $fimport$9 (result i64)))
 (import "env" "bench_clock" (func $fimport$10 (result i64)))
 (global $global$0 (mut i32) (i32.const 1296))
 (global $global$1 (mut i32) (i32.const 8388608))
 (global $global$2 (mut i32) (i32.const 0))
 (global $global$3 (mut i32) (i32.const 0))
 (global $global$4 (mut i32) (i32.const 0))
 (global $global$5 (mut i32) (i32.const 0))
 (global $global$6 (mut i32) (i32.const 0))
 (global $global$7 (mut i32) (i32.const -1))
 (memory $0 16 256)
 (data $0 (i32.const 1208) "activation stack exhausted")
 (data $1 (i32.const 1234) "linear memory exhausted")
 (data $2 (i32.const 1257) "assertion failed")
 (data $3 (i32.const 1273) "array capacity exceeded")
 (table $0 2 funcref)
 (elem $0 (i32.const 0) $6 $7)
 (export "memory" (memory $0))
 (export "_start" (func $2))
 (func $0 (param $0 i32) (param $1 i32) (param $2 i32) (param $3 f64) (param $4 f64) (result i64)
  (local $5 i32)
  (local $6 i32)
  (local $7 i32)
  (local $8 i32)
  (local $9 i32)
  (local $10 i32)
  (local $11 i32)
  (local $12 i32)
  (local $13 i32)
  (local $14 i32)
  (local $15 i32)
  (local $16 i32)
  (local $17 i32)
  (local $18 i32)
  (local $19 i32)
  (local $20 i32)
  (local $21 i32)
  (local $22 i64)
  (local $23 i32)
  (local $24 i32)
  (local $25 i32)
  (local $26 f64)
  (local $27 f64)
  (local $28 i32)
  (local $29 i32)
  (local $30 f64)
  (local $31 i32)
  (local $32 i64)
  (local $33 i32)
  (local $34 i32)
  (local $35 i32)
  (local $36 i32)
  (local $37 i32)
  (local $38 f64)
  (local $39 i32)
  (local $40 f64)
  (local $41 i32)
  (local $42 f64)
  (local $43 i32)
  (local $44 i32)
  (local $45 i32)
  (local $46 i32)
  (local $47 f64)
  (local $48 i32)
  (local $49 f64)
  (local $50 i32)
  (local $51 f64)
  (local $52 i32)
  (local $53 f64)
  (local $54 i32)
  (local $55 i32)
  (local $56 i32)
  (local $57 i32)
  (local $58 i64)
  (local $59 i32)
  (local $60 i32)
  (local $61 i32)
  (local.set $5
   (global.get $global$0)
  )
  (local.set $61
   (i32.add
    (local.get $5)
    (i32.const 128)
   )
  )
  (if
   (i32.or
    (i32.lt_u
     (local.get $61)
     (local.get $5)
    )
    (i32.gt_u
     (local.get $61)
     (i32.const 8388608)
    )
   )
   (then
    (call $fimport$7
     (i32.const 1208)
     (i32.const 26)
     (i32.const 7)
    )
    (unreachable)
   )
  )
  (if
   (i32.gt_u
    (local.get $61)
    (i32.shl
     (memory.size)
     (i32.const 16)
    )
   )
   (then
    (if
     (i32.eq
      (memory.grow
       (i32.sub
        (i32.add
         (i32.shr_u
          (local.get $61)
          (i32.const 16)
         )
         (i32.eqz
          (i32.eqz
           (i32.and
            (local.get $61)
            (i32.const 65535)
           )
          )
         )
        )
        (memory.size)
       )
      )
      (i32.const -1)
     )
     (then
      (call $fimport$7
       (i32.const 1234)
       (i32.const 23)
       (i32.const 7)
      )
      (unreachable)
     )
    )
   )
  )
  (global.set $global$0
   (local.get $61)
  )
  (local.set $6
   (global.get $global$1)
  )
  (local.set $7
   (global.get $global$5)
  )
  (local.set $8
   (local.get $5)
  )
  (local.set $9
   (i32.add
    (local.get $5)
    (i32.const 4)
   )
  )
  (local.set $10
   (i32.add
    (local.get $5)
    (i32.const 8)
   )
  )
  (local.set $11
   (i32.add
    (local.get $5)
    (i32.const 16)
   )
  )
  (local.set $12
   (i32.add
    (local.get $5)
    (i32.const 24)
   )
  )
  (local.set $13
   (i32.add
    (local.get $5)
    (i32.const 32)
   )
  )
  (local.set $14
   (i32.add
    (local.get $5)
    (i32.const 40)
   )
  )
  (local.set $15
   (i32.add
    (local.get $5)
    (i32.const 48)
   )
  )
  (local.set $16
   (i32.add
    (local.get $5)
    (i32.const 56)
   )
  )
  (local.set $17
   (i32.add
    (local.get $5)
    (i32.const 64)
   )
  )
  (local.set $18
   (i32.add
    (local.get $5)
    (i32.const 72)
   )
  )
  (local.set $19
   (i32.add
    (local.get $5)
    (i32.const 80)
   )
  )
  (local.set $20
   (i32.add
    (local.get $5)
    (i32.const 88)
   )
  )
  (local.set $21
   (i32.add
    (local.get $5)
    (i32.const 96)
   )
  )
  (i32.store
   (i32.add
    (local.get $5)
    (i32.const 104)
   )
   (global.get $global$4)
  )
  (i32.store offset=4
   (i32.add
    (local.get $5)
    (i32.const 104)
   )
   (i32.const 10)
  )
  (global.set $global$4
   (i32.add
    (local.get $5)
    (i32.const 104)
   )
  )
  (block $block2
   (local.set $23
    (local.get $0)
   )
   (i32.store
    (call $5
     (local.get $8)
    )
    (local.get $23)
   )
   (local.set $24
    (local.get $1)
   )
   (i32.store
    (call $5
     (local.get $9)
    )
    (local.get $24)
   )
   (local.set $25
    (local.get $2)
   )
   (i32.store
    (call $5
     (local.get $10)
    )
    (local.get $25)
   )
   (local.set $26
    (local.get $3)
   )
   (f64.store
    (call $5
     (local.get $11)
    )
    (local.get $26)
   )
   (local.set $27
    (local.get $4)
   )
   (f64.store
    (call $5
     (local.get $12)
    )
    (local.get $27)
   )
   (local.set $28
    (local.get $13)
   )
   (local.set $30
    (f64.add
     (f64.const -1.25)
     (block (result f64)
      (local.set $29
       (i32.load
        (call $5
         (local.get $8)
        )
       )
      )
      (f64.mul
       (f64.add
        (f64.convert_i32_u
         (local.get $29)
        )
        (f64.const 0.5)
       )
       (f64.load
        (call $5
         (local.get $12)
        )
       )
      )
     )
    )
   )
   (f64.store
    (call $5
     (local.get $28)
    )
    (local.get $30)
   )
   (local.set $31
    (local.get $14)
   )
   (local.set $32
    (i64.const 0)
   )
   (i64.store
    (call $5
     (local.get $31)
    )
    (local.get $32)
   )
   (local.set $33
    (local.get $15)
   )
   (local.set $34
    (i32.const 0)
   )
   (i32.store
    (call $5
     (local.get $33)
    )
    (local.get $34)
   )
   (local.set $35
    (global.get $global$0)
   )
   (block $block
    (loop $label1
     (br_if $block
      (i32.eqz
       (i32.lt_u
        (i32.load
         (call $5
          (local.get $15)
         )
        )
        (i32.load
         (call $5
          (local.get $9)
         )
        )
       )
      )
     )
     (local.set $36
      (local.get $16)
     )
     (local.set $38
      (f64.add
       (f64.const -2)
       (block (result f64)
        (local.set $37
         (i32.load
          (call $5
           (local.get $15)
          )
         )
        )
        (f64.mul
         (f64.add
          (f64.convert_i32_u
           (local.get $37)
          )
          (f64.const 0.5)
         )
         (f64.load
          (call $5
           (local.get $11)
          )
         )
        )
       )
      )
     )
     (f64.store
      (call $5
       (local.get $36)
      )
      (local.get $38)
     )
     (local.set $39
      (local.get $17)
     )
     (local.set $40
      (f64.const 0)
     )
     (f64.store
      (call $5
       (local.get $39)
      )
      (local.get $40)
     )
     (local.set $41
      (local.get $18)
     )
     (local.set $42
      (f64.const 0)
     )
     (f64.store
      (call $5
       (local.get $41)
      )
      (local.get $42)
     )
     (local.set $43
      (local.get $19)
     )
     (local.set $44
      (i32.const 0)
     )
     (i32.store
      (call $5
       (local.get $43)
      )
      (local.get $44)
     )
     (local.set $45
      (global.get $global$0)
     )
     (block $block1
      (loop $label
       (br_if $block1
        (i32.eqz
         (i32.lt_u
          (i32.load
           (call $5
            (local.get $19)
           )
          )
          (i32.load
           (call $5
            (local.get $10)
           )
          )
         )
        )
       )
       (local.set $46
        (local.get $20)
       )
       (local.set $47
        (f64.mul
         (f64.load
          (call $5
           (local.get $17)
          )
         )
         (f64.load
          (call $5
           (local.get $17)
          )
         )
        )
       )
       (f64.store
        (call $5
         (local.get $46)
        )
        (local.get $47)
       )
       (local.set $48
        (local.get $21)
       )
       (local.set $49
        (f64.mul
         (f64.load
          (call $5
           (local.get $18)
          )
         )
         (f64.load
          (call $5
           (local.get $18)
          )
         )
        )
       )
       (f64.store
        (call $5
         (local.get $48)
        )
        (local.get $49)
       )
       (if
        (f64.gt
         (f64.add
          (f64.load
           (call $5
            (local.get $20)
           )
          )
          (f64.load
           (call $5
            (local.get $21)
           )
          )
         )
         (f64.const 4)
        )
        (then
         (global.set $global$0
          (local.get $45)
         )
         (br $block1)
        )
       )
       (local.set $50
        (local.get $18)
       )
       (local.set $51
        (f64.add
         (f64.mul
          (f64.mul
           (f64.const 2)
           (f64.load
            (call $5
             (local.get $17)
            )
           )
          )
          (f64.load
           (call $5
            (local.get $18)
           )
          )
         )
         (f64.load
          (call $5
           (local.get $13)
          )
         )
        )
       )
       (f64.store
        (call $5
         (local.get $50)
        )
        (local.get $51)
       )
       (local.set $52
        (local.get $17)
       )
       (local.set $53
        (f64.add
         (f64.sub
          (f64.load
           (call $5
            (local.get $20)
           )
          )
          (f64.load
           (call $5
            (local.get $21)
           )
          )
         )
         (f64.load
          (call $5
           (local.get $16)
          )
         )
        )
       )
       (f64.store
        (call $5
         (local.get $52)
        )
        (local.get $53)
       )
       (local.set $54
        (local.get $19)
       )
       (local.set $55
        (i32.add
         (i32.load
          (call $5
           (local.get $54)
          )
         )
         (i32.const 1)
        )
       )
       (i32.store
        (call $5
         (local.get $54)
        )
        (local.get $55)
       )
       (br $label)
      )
     )
     (local.set $56
      (local.get $14)
     )
     (local.set $58
      (i64.add
       (i64.load
        (call $5
         (local.get $56)
        )
       )
       (block (result i64)
        (local.set $57
         (i32.load
          (call $5
           (local.get $19)
          )
         )
        )
        (i64.extend_i32_u
         (local.get $57)
        )
       )
      )
     )
     (i64.store
      (call $5
       (local.get $56)
      )
      (local.get $58)
     )
     (local.set $59
      (local.get $15)
     )
     (local.set $60
      (i32.add
       (i32.load
        (call $5
         (local.get $59)
        )
       )
       (i32.const 1)
      )
     )
     (i32.store
      (call $5
       (local.get $59)
      )
      (local.get $60)
     )
     (br $label1)
    )
   )
   (local.set $22
    (i64.load
     (call $5
      (local.get $14)
     )
    )
   )
   (br $block2)
  )
  (if
   (i32.eq
    (global.get $global$2)
    (i32.add
     (local.get $5)
     (i32.const 104)
    )
   )
   (then
    (local.set $22
     (i64.load
      (call $5
       (i32.add
        (local.get $5)
        (i32.const 120)
       )
      )
     )
    )
    (global.set $global$2
     (i32.const 0)
    )
   )
  )
  (global.set $global$4
   (i32.load
    (i32.add
     (local.get $5)
     (i32.const 104)
    )
   )
  )
  (if
   (i32.eqz
    (global.get $global$2)
   )
   (then
   )
  )
  (global.set $global$1
   (local.get $6)
  )
  (global.set $global$5
   (local.get $7)
  )
  (global.set $global$0
   (local.get $5)
  )
  (local.get $22)
 )
 (func $1
  (local $0 i32)
  (local $1 i32)
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local $5 i32)
  (local $6 i32)
  (local $7 i32)
  (local $8 i32)
  (local $9 i32)
  (local $10 i32)
  (local $11 i32)
  (local $12 i32)
  (local $13 i32)
  (local $14 i32)
  (local $15 i32)
  (local $16 i32)
  (local $17 i32)
  (local $18 i32)
  (local $19 i32)
  (local $20 i32)
  (local $21 i32)
  (local $22 i32)
  (local $23 i32)
  (local $24 i32)
  (local $25 i32)
  (local $26 i32)
  (local $27 i64)
  (local $28 i64)
  (local $29 i32)
  (local $30 i64)
  (local $31 i64)
  (local $32 i32)
  (local $33 i64)
  (local $34 i64)
  (local $35 i32)
  (local $36 i64)
  (local $37 i32)
  (local $38 i32)
  (local $39 i64)
  (local $40 i32)
  (local $41 i32)
  (local $42 i32)
  (local $43 f64)
  (local $44 i32)
  (local $45 i32)
  (local $46 f64)
  (local $47 i32)
  (local $48 i64)
  (local $49 i32)
  (local $50 i32)
  (local $51 i32)
  (local $52 i64)
  (local $53 i64)
  (local $54 i32)
  (local $55 i32)
  (local $56 i64)
  (local $57 i32)
  (local $58 i32)
  (local $59 i32)
  (local $60 i32)
  (local $61 i32)
  (local $62 i32)
  (local $63 i32)
  (local $64 f64)
  (local $65 i32)
  (local $66 f64)
  (local $67 i32)
  (local $68 i32)
  (local $69 i32)
  (local $70 f64)
  (local $71 i32)
  (local $72 i64)
  (local $73 i32)
  (local $74 i32)
  (local $75 i32)
  (local $76 i32)
  (local $77 i32)
  (local $78 f64)
  (local $79 i32)
  (local $80 f64)
  (local $81 i32)
  (local $82 f64)
  (local $83 i32)
  (local $84 i32)
  (local $85 i32)
  (local $86 i32)
  (local $87 f64)
  (local $88 i32)
  (local $89 f64)
  (local $90 i32)
  (local $91 f64)
  (local $92 i32)
  (local $93 f64)
  (local $94 i32)
  (local $95 i32)
  (local $96 i32)
  (local $97 i32)
  (local $98 i64)
  (local $99 i32)
  (local $100 i32)
  (local $101 i64)
  (local $102 i32)
  (local $103 i32)
  (local $104 i32)
  (local $105 i64)
  (local $106 i64)
  (local $107 i32)
  (local $108 i64)
  (local $109 i32)
  (local $110 i64)
  (local $111 i32)
  (local.set $0
   (global.get $global$0)
  )
  (local.set $111
   (i32.add
    (local.get $0)
    (i32.const 200)
   )
  )
  (if
   (i32.or
    (i32.lt_u
     (local.get $111)
     (local.get $0)
    )
    (i32.gt_u
     (local.get $111)
     (i32.const 8388608)
    )
   )
   (then
    (call $fimport$7
     (i32.const 1208)
     (i32.const 26)
     (i32.const 30)
    )
    (unreachable)
   )
  )
  (if
   (i32.gt_u
    (local.get $111)
    (i32.shl
     (memory.size)
     (i32.const 16)
    )
   )
   (then
    (if
     (i32.eq
      (memory.grow
       (i32.sub
        (i32.add
         (i32.shr_u
          (local.get $111)
          (i32.const 16)
         )
         (i32.eqz
          (i32.eqz
           (i32.and
            (local.get $111)
            (i32.const 65535)
           )
          )
         )
        )
        (memory.size)
       )
      )
      (i32.const -1)
     )
     (then
      (call $fimport$7
       (i32.const 1234)
       (i32.const 23)
       (i32.const 30)
      )
      (unreachable)
     )
    )
   )
  )
  (global.set $global$0
   (local.get $111)
  )
  (local.set $1
   (local.get $0)
  )
  (local.set $2
   (i32.add
    (local.get $0)
    (i32.const 8)
   )
  )
  (local.set $3
   (i32.add
    (local.get $0)
    (i32.const 16)
   )
  )
  (local.set $4
   (i32.add
    (local.get $0)
    (i32.const 24)
   )
  )
  (local.set $5
   (i32.add
    (local.get $0)
    (i32.const 28)
   )
  )
  (local.set $6
   (i32.add
    (local.get $0)
    (i32.const 32)
   )
  )
  (local.set $7
   (i32.add
    (local.get $0)
    (i32.const 40)
   )
  )
  (local.set $8
   (i32.add
    (local.get $0)
    (i32.const 48)
   )
  )
  (local.set $9
   (i32.add
    (local.get $0)
    (i32.const 56)
   )
  )
  (local.set $10
   (i32.add
    (local.get $0)
    (i32.const 64)
   )
  )
  (local.set $11
   (i32.add
    (local.get $0)
    (i32.const 72)
   )
  )
  (local.set $12
   (i32.add
    (local.get $0)
    (i32.const 80)
   )
  )
  (local.set $13
   (i32.add
    (local.get $0)
    (i32.const 84)
   )
  )
  (local.set $14
   (i32.add
    (local.get $0)
    (i32.const 88)
   )
  )
  (local.set $15
   (i32.add
    (local.get $0)
    (i32.const 96)
   )
  )
  (local.set $16
   (i32.add
    (local.get $0)
    (i32.const 104)
   )
  )
  (local.set $17
   (i32.add
    (local.get $0)
    (i32.const 112)
   )
  )
  (local.set $18
   (i32.add
    (local.get $0)
    (i32.const 120)
   )
  )
  (local.set $19
   (i32.add
    (local.get $0)
    (i32.const 128)
   )
  )
  (local.set $20
   (i32.add
    (local.get $0)
    (i32.const 136)
   )
  )
  (local.set $21
   (i32.add
    (local.get $0)
    (i32.const 144)
   )
  )
  (local.set $22
   (i32.add
    (local.get $0)
    (i32.const 152)
   )
  )
  (local.set $23
   (i32.add
    (local.get $0)
    (i32.const 160)
   )
  )
  (local.set $24
   (i32.add
    (local.get $0)
    (i32.const 168)
   )
  )
  (local.set $25
   (i32.add
    (local.get $0)
    (i32.const 176)
   )
  )
  (i32.store
   (i32.add
    (local.get $0)
    (i32.const 184)
   )
   (global.get $global$4)
  )
  (i32.store offset=4
   (i32.add
    (local.get $0)
    (i32.const 184)
   )
   (i32.const 132)
  )
  (global.set $global$4
   (i32.add
    (local.get $0)
    (i32.const 184)
   )
  )
  (block $block
   (local.set $26
    (local.get $1)
   )
   (local.set $27
    (call $fimport$9)
   )
   (br_if $block
    (global.get $global$2)
   )
   (local.set $28
    (local.get $27)
   )
   (i64.store
    (call $5
     (local.get $26)
    )
    (local.get $28)
   )
   (local.set $29
    (local.get $2)
   )
   (local.set $30
    (call $fimport$9)
   )
   (br_if $block
    (global.get $global$2)
   )
   (local.set $31
    (local.get $30)
   )
   (i64.store
    (call $5
     (local.get $29)
    )
    (local.get $31)
   )
   (local.set $32
    (local.get $3)
   )
   (local.set $33
    (call $fimport$9)
   )
   (br_if $block
    (global.get $global$2)
   )
   (local.set $34
    (local.get $33)
   )
   (i64.store
    (call $5
     (local.get $32)
    )
    (local.get $34)
   )
   (if
    (i32.eqz
     (if (result i32)
      (i64.gt_s
       (i64.load
        (call $5
         (local.get $1)
        )
       )
       (i64.const 0)
      )
      (then
       (i64.le_s
        (i64.load
         (call $5
          (local.get $1)
         )
        )
        (i64.const 4294967295)
       )
      )
      (else
       (i32.const 0)
      )
     )
    )
    (then
     (call $fimport$7
      (i32.const 1257)
      (i32.const 16)
      (i32.const 34)
     )
     (unreachable)
    )
   )
   (if
    (i32.eqz
     (if (result i32)
      (i64.gt_s
       (i64.load
        (call $5
         (local.get $2)
        )
       )
       (i64.const 0)
      )
      (then
       (i64.le_s
        (i64.load
         (call $5
          (local.get $2)
         )
        )
        (i64.const 4294967295)
       )
      )
      (else
       (i32.const 0)
      )
     )
    )
    (then
     (call $fimport$7
      (i32.const 1257)
      (i32.const 16)
      (i32.const 35)
     )
     (unreachable)
    )
   )
   (if
    (i32.eqz
     (i64.eq
      (i64.load
       (call $5
        (local.get $3)
       )
      )
      (i64.const 1)
     )
    )
    (then
     (call $fimport$7
      (i32.const 1257)
      (i32.const 16)
      (i32.const 36)
     )
     (unreachable)
    )
   )
   (local.set $35
    (local.get $4)
   )
   (local.set $36
    (i64.load
     (call $5
      (local.get $1)
     )
    )
   )
   (local.set $37
    (i32.wrap_i64
     (local.get $36)
    )
   )
   (i32.store
    (call $5
     (local.get $35)
    )
    (local.get $37)
   )
   (local.set $38
    (local.get $5)
   )
   (local.set $39
    (i64.load
     (call $5
      (local.get $2)
     )
    )
   )
   (local.set $40
    (i32.wrap_i64
     (local.get $39)
    )
   )
   (i32.store
    (call $5
     (local.get $38)
    )
    (local.get $40)
   )
   (local.set $41
    (local.get $6)
   )
   (local.set $43
    (f64.div
     (f64.const 2.5)
     (block (result f64)
      (local.set $42
       (i32.load
        (call $5
         (local.get $4)
        )
       )
      )
      (f64.convert_i32_u
       (local.get $42)
      )
     )
    )
   )
   (f64.store
    (call $5
     (local.get $41)
    )
    (local.get $43)
   )
   (local.set $44
    (local.get $7)
   )
   (local.set $46
    (f64.div
     (f64.const 2.5)
     (block (result f64)
      (local.set $45
       (i32.load
        (call $5
         (local.get $4)
        )
       )
      )
      (f64.convert_i32_u
       (local.get $45)
      )
     )
    )
   )
   (f64.store
    (call $5
     (local.get $44)
    )
    (local.get $46)
   )
   (local.set $47
    (local.get $8)
   )
   (local.set $48
    (i64.const 0)
   )
   (i64.store
    (call $5
     (local.get $47)
    )
    (local.get $48)
   )
   (local.set $49
    (local.get $9)
   )
   (local.set $50
    (i32.const 0)
   )
   (i32.store
    (call $5
     (local.get $49)
    )
    (local.get $50)
   )
   (local.set $51
    (local.get $10)
   )
   (local.set $52
    (call $fimport$10)
   )
   (br_if $block
    (global.get $global$2)
   )
   (local.set $53
    (local.get $52)
   )
   (i64.store
    (call $5
     (local.get $51)
    )
    (local.get $53)
   )
   (local.set $54
    (global.get $global$0)
   )
   (block $block1
    (loop $label2
     (br_if $block1
      (i32.eqz
       (i32.lt_u
        (i32.load
         (call $5
          (local.get $9)
         )
        )
        (i32.load
         (call $5
          (local.get $4)
         )
        )
       )
      )
     )
     (local.set $55
      (local.get $8)
     )
     (local.set $101
      (i64.add
       (i64.load
        (call $5
         (local.get $55)
        )
       )
       (block (result i64)
        (local.set $57
         (local.get $12)
        )
        (local.set $58
         (i32.load
          (call $5
           (local.get $9)
          )
         )
        )
        (i32.store
         (call $5
          (local.get $57)
         )
         (local.get $58)
        )
        (local.set $59
         (local.get $13)
        )
        (local.set $60
         (i32.load
          (call $5
           (local.get $4)
          )
         )
        )
        (i32.store
         (call $5
          (local.get $59)
         )
         (local.get $60)
        )
        (local.set $61
         (local.get $14)
        )
        (local.set $62
         (i32.load
          (call $5
           (local.get $5)
          )
         )
        )
        (i32.store
         (call $5
          (local.get $61)
         )
         (local.get $62)
        )
        (local.set $63
         (local.get $15)
        )
        (local.set $64
         (f64.load
          (call $5
           (local.get $6)
          )
         )
        )
        (f64.store
         (call $5
          (local.get $63)
         )
         (local.get $64)
        )
        (local.set $65
         (local.get $16)
        )
        (local.set $66
         (f64.load
          (call $5
           (local.get $7)
          )
         )
        )
        (f64.store
         (call $5
          (local.get $65)
         )
         (local.get $66)
        )
        (local.set $67
         (global.get $global$0)
        )
        (block $block4
         (local.set $68
          (local.get $17)
         )
         (local.set $70
          (f64.add
           (f64.const -1.25)
           (block (result f64)
            (local.set $69
             (i32.load
              (call $5
               (local.get $12)
              )
             )
            )
            (f64.mul
             (f64.add
              (f64.convert_i32_u
               (local.get $69)
              )
              (f64.const 0.5)
             )
             (f64.load
              (call $5
               (local.get $16)
              )
             )
            )
           )
          )
         )
         (f64.store
          (call $5
           (local.get $68)
          )
          (local.get $70)
         )
         (local.set $71
          (local.get $18)
         )
         (local.set $72
          (i64.const 0)
         )
         (i64.store
          (call $5
           (local.get $71)
          )
          (local.get $72)
         )
         (local.set $73
          (local.get $19)
         )
         (local.set $74
          (i32.const 0)
         )
         (i32.store
          (call $5
           (local.get $73)
          )
          (local.get $74)
         )
         (local.set $75
          (global.get $global$0)
         )
         (block $block2
          (loop $label1
           (br_if $block2
            (i32.eqz
             (i32.lt_u
              (i32.load
               (call $5
                (local.get $19)
               )
              )
              (i32.load
               (call $5
                (local.get $13)
               )
              )
             )
            )
           )
           (local.set $76
            (local.get $20)
           )
           (local.set $78
            (f64.add
             (f64.const -2)
             (block (result f64)
              (local.set $77
               (i32.load
                (call $5
                 (local.get $19)
                )
               )
              )
              (f64.mul
               (f64.add
                (f64.convert_i32_u
                 (local.get $77)
                )
                (f64.const 0.5)
               )
               (f64.load
                (call $5
                 (local.get $15)
                )
               )
              )
             )
            )
           )
           (f64.store
            (call $5
             (local.get $76)
            )
            (local.get $78)
           )
           (local.set $79
            (local.get $21)
           )
           (local.set $80
            (f64.const 0)
           )
           (f64.store
            (call $5
             (local.get $79)
            )
            (local.get $80)
           )
           (local.set $81
            (local.get $22)
           )
           (local.set $82
            (f64.const 0)
           )
           (f64.store
            (call $5
             (local.get $81)
            )
            (local.get $82)
           )
           (local.set $83
            (local.get $23)
           )
           (local.set $84
            (i32.const 0)
           )
           (i32.store
            (call $5
             (local.get $83)
            )
            (local.get $84)
           )
           (local.set $85
            (global.get $global$0)
           )
           (block $block3
            (loop $label
             (br_if $block3
              (i32.eqz
               (i32.lt_u
                (i32.load
                 (call $5
                  (local.get $23)
                 )
                )
                (i32.load
                 (call $5
                  (local.get $14)
                 )
                )
               )
              )
             )
             (local.set $86
              (local.get $24)
             )
             (local.set $87
              (f64.mul
               (f64.load
                (call $5
                 (local.get $21)
                )
               )
               (f64.load
                (call $5
                 (local.get $21)
                )
               )
              )
             )
             (f64.store
              (call $5
               (local.get $86)
              )
              (local.get $87)
             )
             (local.set $88
              (local.get $25)
             )
             (local.set $89
              (f64.mul
               (f64.load
                (call $5
                 (local.get $22)
                )
               )
               (f64.load
                (call $5
                 (local.get $22)
                )
               )
              )
             )
             (f64.store
              (call $5
               (local.get $88)
              )
              (local.get $89)
             )
             (if
              (f64.gt
               (f64.add
                (f64.load
                 (call $5
                  (local.get $24)
                 )
                )
                (f64.load
                 (call $5
                  (local.get $25)
                 )
                )
               )
               (f64.const 4)
              )
              (then
               (global.set $global$0
                (local.get $85)
               )
               (br $block3)
              )
             )
             (local.set $90
              (local.get $22)
             )
             (local.set $91
              (f64.add
               (f64.mul
                (f64.mul
                 (f64.const 2)
                 (f64.load
                  (call $5
                   (local.get $21)
                  )
                 )
                )
                (f64.load
                 (call $5
                  (local.get $22)
                 )
                )
               )
               (f64.load
                (call $5
                 (local.get $17)
                )
               )
              )
             )
             (f64.store
              (call $5
               (local.get $90)
              )
              (local.get $91)
             )
             (local.set $92
              (local.get $21)
             )
             (local.set $93
              (f64.add
               (f64.sub
                (f64.load
                 (call $5
                  (local.get $24)
                 )
                )
                (f64.load
                 (call $5
                  (local.get $25)
                 )
                )
               )
               (f64.load
                (call $5
                 (local.get $20)
                )
               )
              )
             )
             (f64.store
              (call $5
               (local.get $92)
              )
              (local.get $93)
             )
             (local.set $94
              (local.get $23)
             )
             (local.set $95
              (i32.add
               (i32.load
                (call $5
                 (local.get $94)
                )
               )
               (i32.const 1)
              )
             )
             (i32.store
              (call $5
               (local.get $94)
              )
              (local.get $95)
             )
             (br $label)
            )
           )
           (local.set $96
            (local.get $18)
           )
           (local.set $98
            (i64.add
             (i64.load
              (call $5
               (local.get $96)
              )
             )
             (block (result i64)
              (local.set $97
               (i32.load
                (call $5
                 (local.get $23)
                )
               )
              )
              (i64.extend_i32_u
               (local.get $97)
              )
             )
            )
           )
           (i64.store
            (call $5
             (local.get $96)
            )
            (local.get $98)
           )
           (local.set $99
            (local.get $19)
           )
           (local.set $100
            (i32.add
             (i32.load
              (call $5
               (local.get $99)
              )
             )
             (i32.const 1)
            )
           )
           (i32.store
            (call $5
             (local.get $99)
            )
            (local.get $100)
           )
           (br $label1)
          )
         )
         (local.set $56
          (i64.load
           (call $5
            (local.get $18)
           )
          )
         )
         (global.set $global$0
          (local.get $67)
         )
         (br $block4)
        )
        (local.get $56)
       )
      )
     )
     (i64.store
      (call $5
       (local.get $55)
      )
      (local.get $101)
     )
     (local.set $102
      (local.get $9)
     )
     (local.set $103
      (i32.add
       (i32.load
        (call $5
         (local.get $102)
        )
       )
       (i32.const 1)
      )
     )
     (i32.store
      (call $5
       (local.get $102)
      )
      (local.get $103)
     )
     (br $label2)
    )
   )
   (local.set $104
    (local.get $11)
   )
   (local.set $105
    (call $fimport$10)
   )
   (br_if $block
    (global.get $global$2)
   )
   (local.set $106
    (i64.sub
     (local.get $105)
     (i64.load
      (call $5
       (local.get $10)
      )
     )
    )
   )
   (i64.store
    (call $5
     (local.get $104)
    )
    (local.get $106)
   )
   (local.set $107
    (global.get $global$0)
   )
   (local.set $108
    (i64.load
     (call $5
      (local.get $8)
     )
    )
   )
   (call $fimport$2
    (local.get $108)
   )
   (call $fimport$6)
   (global.set $global$0
    (local.get $107)
   )
   (local.set $109
    (global.get $global$0)
   )
   (local.set $110
    (i64.load
     (call $5
      (local.get $11)
     )
    )
   )
   (call $fimport$1
    (local.get $110)
   )
   (call $fimport$6)
   (global.set $global$0
    (local.get $109)
   )
  )
  (if
   (i32.eq
    (global.get $global$2)
    (i32.add
     (local.get $0)
     (i32.const 184)
    )
   )
   (then
    (global.set $global$2
     (i32.const 0)
    )
   )
  )
  (global.set $global$4
   (i32.load
    (i32.add
     (local.get $0)
     (i32.const 184)
    )
   )
  )
  (if
   (i32.eqz
    (global.get $global$2)
   )
   (then
   )
  )
  (global.set $global$0
   (local.get $0)
  )
 )
 (func $2
  (local $0 i32)
  (local $1 i32)
  (local $2 i32)
  (local $3 i32)
  (local $4 i32)
  (local $5 f64)
  (local $6 i32)
  (local $7 f64)
  (local $8 i32)
  (local $9 f64)
  (local $10 i32)
  (local $11 f64)
  (local $12 i32)
  (local $13 f64)
  (local $14 i32)
  (local $15 f64)
  (local $16 i32)
  (local $17 f64)
  (local $18 i32)
  (local $19 f64)
  (local $20 i32)
  (local $21 f64)
  (local $22 i32)
  (local $23 f64)
  (local $24 i32)
  (local $25 f64)
  (local $26 i32)
  (local $27 f64)
  (local $28 i32)
  (local $29 f64)
  (local $30 i32)
  (local $31 f64)
  (local $32 i32)
  (local $33 f64)
  (local $34 i32)
  (local $35 f64)
  (local $36 i32)
  (local $37 f64)
  (local $38 i32)
  (local $39 f64)
  (local $40 i32)
  (local $41 f64)
  (local $42 i32)
  (local $43 f64)
  (local $44 i32)
  (local $45 f64)
  (local $46 i32)
  (local $47 f64)
  (local $48 i32)
  (local $49 f64)
  (local $50 i32)
  (local $51 i32)
  (local $52 i32)
  (local $53 i32)
  (local.set $0
   (global.get $global$0)
  )
  (local.set $53
   (i32.add
    (local.get $0)
    (i32.const 200)
   )
  )
  (if
   (i32.or
    (i32.lt_u
     (local.get $53)
     (local.get $0)
    )
    (i32.gt_u
     (local.get $53)
     (i32.const 8388608)
    )
   )
   (then
    (call $fimport$7
     (i32.const 1208)
     (i32.const 26)
     (i32.const 0)
    )
    (unreachable)
   )
  )
  (if
   (i32.gt_u
    (local.get $53)
    (i32.shl
     (memory.size)
     (i32.const 16)
    )
   )
   (then
    (if
     (i32.eq
      (memory.grow
       (i32.sub
        (i32.add
         (i32.shr_u
          (local.get $53)
          (i32.const 16)
         )
         (i32.eqz
          (i32.eqz
           (i32.and
            (local.get $53)
            (i32.const 65535)
           )
          )
         )
        )
        (memory.size)
       )
      )
      (i32.const -1)
     )
     (then
      (call $fimport$7
       (i32.const 1234)
       (i32.const 23)
       (i32.const 0)
      )
      (unreachable)
     )
    )
   )
  )
  (global.set $global$0
   (local.get $53)
  )
  (i32.store
   (local.get $0)
   (global.get $global$4)
  )
  (i32.store offset=4
   (local.get $0)
   (i32.const 0)
  )
  (global.set $global$4
   (local.get $0)
  )
  (block
   (local.set $1
    (i32.const 1024)
   )
   (local.set $2
    (i32.add
     (local.get $0)
     (i32.const 16)
    )
   )
   (memory.fill
    (local.get $2)
    (i32.const 0)
    (i32.const 184)
   )
   (local.set $3
    (i32.const 23)
   )
   (if
    (i32.gt_u
     (local.get $3)
     (i32.const 23)
    )
    (then
     (call $fimport$7
      (i32.const 1273)
      (i32.const 23)
      (i32.const 1112)
     )
     (unreachable)
    )
   )
   (local.set $4
    (i32.add
     (local.get $2)
     (i32.const 0)
    )
   )
   (local.set $5
    (f64.const 1)
   )
   (f64.store
    (call $5
     (local.get $4)
    )
    (local.get $5)
   )
   (local.set $6
    (i32.add
     (local.get $2)
     (i32.const 8)
    )
   )
   (local.set $7
    (f64.const 10)
   )
   (f64.store
    (call $5
     (local.get $6)
    )
    (local.get $7)
   )
   (local.set $8
    (i32.add
     (local.get $2)
     (i32.const 16)
    )
   )
   (local.set $9
    (f64.const 100)
   )
   (f64.store
    (call $5
     (local.get $8)
    )
    (local.get $9)
   )
   (local.set $10
    (i32.add
     (local.get $2)
     (i32.const 24)
    )
   )
   (local.set $11
    (f64.const 1e3)
   )
   (f64.store
    (call $5
     (local.get $10)
    )
    (local.get $11)
   )
   (local.set $12
    (i32.add
     (local.get $2)
     (i32.const 32)
    )
   )
   (local.set $13
    (f64.const 1e4)
   )
   (f64.store
    (call $5
     (local.get $12)
    )
    (local.get $13)
   )
   (local.set $14
    (i32.add
     (local.get $2)
     (i32.const 40)
    )
   )
   (local.set $15
    (f64.const 1e5)
   )
   (f64.store
    (call $5
     (local.get $14)
    )
    (local.get $15)
   )
   (local.set $16
    (i32.add
     (local.get $2)
     (i32.const 48)
    )
   )
   (local.set $17
    (f64.const 1e6)
   )
   (f64.store
    (call $5
     (local.get $16)
    )
    (local.get $17)
   )
   (local.set $18
    (i32.add
     (local.get $2)
     (i32.const 56)
    )
   )
   (local.set $19
    (f64.const 1e7)
   )
   (f64.store
    (call $5
     (local.get $18)
    )
    (local.get $19)
   )
   (local.set $20
    (i32.add
     (local.get $2)
     (i32.const 64)
    )
   )
   (local.set $21
    (f64.const 1e8)
   )
   (f64.store
    (call $5
     (local.get $20)
    )
    (local.get $21)
   )
   (local.set $22
    (i32.add
     (local.get $2)
     (i32.const 72)
    )
   )
   (local.set $23
    (f64.const 1e9)
   )
   (f64.store
    (call $5
     (local.get $22)
    )
    (local.get $23)
   )
   (local.set $24
    (i32.add
     (local.get $2)
     (i32.const 80)
    )
   )
   (local.set $25
    (f64.const 1e10)
   )
   (f64.store
    (call $5
     (local.get $24)
    )
    (local.get $25)
   )
   (local.set $26
    (i32.add
     (local.get $2)
     (i32.const 88)
    )
   )
   (local.set $27
    (f64.const 1e11)
   )
   (f64.store
    (call $5
     (local.get $26)
    )
    (local.get $27)
   )
   (local.set $28
    (i32.add
     (local.get $2)
     (i32.const 96)
    )
   )
   (local.set $29
    (f64.const 1e12)
   )
   (f64.store
    (call $5
     (local.get $28)
    )
    (local.get $29)
   )
   (local.set $30
    (i32.add
     (local.get $2)
     (i32.const 104)
    )
   )
   (local.set $31
    (f64.const 1e13)
   )
   (f64.store
    (call $5
     (local.get $30)
    )
    (local.get $31)
   )
   (local.set $32
    (i32.add
     (local.get $2)
     (i32.const 112)
    )
   )
   (local.set $33
    (f64.const 1e14)
   )
   (f64.store
    (call $5
     (local.get $32)
    )
    (local.get $33)
   )
   (local.set $34
    (i32.add
     (local.get $2)
     (i32.const 120)
    )
   )
   (local.set $35
    (f64.const 1e15)
   )
   (f64.store
    (call $5
     (local.get $34)
    )
    (local.get $35)
   )
   (local.set $36
    (i32.add
     (local.get $2)
     (i32.const 128)
    )
   )
   (local.set $37
    (f64.const 1e16)
   )
   (f64.store
    (call $5
     (local.get $36)
    )
    (local.get $37)
   )
   (local.set $38
    (i32.add
     (local.get $2)
     (i32.const 136)
    )
   )
   (local.set $39
    (f64.const 1e17)
   )
   (f64.store
    (call $5
     (local.get $38)
    )
    (local.get $39)
   )
   (local.set $40
    (i32.add
     (local.get $2)
     (i32.const 144)
    )
   )
   (local.set $41
    (f64.const 1e18)
   )
   (f64.store
    (call $5
     (local.get $40)
    )
    (local.get $41)
   )
   (local.set $42
    (i32.add
     (local.get $2)
     (i32.const 152)
    )
   )
   (local.set $43
    (f64.const 1e19)
   )
   (f64.store
    (call $5
     (local.get $42)
    )
    (local.get $43)
   )
   (local.set $44
    (i32.add
     (local.get $2)
     (i32.const 160)
    )
   )
   (local.set $45
    (f64.const 1e20)
   )
   (f64.store
    (call $5
     (local.get $44)
    )
    (local.get $45)
   )
   (local.set $46
    (i32.add
     (local.get $2)
     (i32.const 168)
    )
   )
   (local.set $47
    (f64.const 1e21)
   )
   (f64.store
    (call $5
     (local.get $46)
    )
    (local.get $47)
   )
   (local.set $48
    (i32.add
     (local.get $2)
     (i32.const 176)
    )
   )
   (local.set $49
    (f64.const 1e22)
   )
   (f64.store
    (call $5
     (local.get $48)
    )
    (local.get $49)
   )
   (local.set $50
    (local.get $2)
   )
   (local.set $51
    (call $5
     (local.get $1)
    )
   )
   (local.set $52
    (call $5
     (local.get $50)
    )
   )
   (memory.copy
    (local.get $51)
    (local.get $52)
    (i32.const 184)
   )
   (call $1)
  )
  (if
   (i32.eq
    (global.get $global$2)
    (local.get $0)
   )
   (then
    (global.set $global$2
     (i32.const 0)
    )
   )
  )
  (global.set $global$4
   (i32.load
    (local.get $0)
   )
  )
  (if
   (i32.eqz
    (global.get $global$2)
   )
   (then
   )
  )
  (global.set $global$0
   (local.get $0)
  )
 )
 (func $3 (param $0 i32) (result i32)
  (local $1 i32)
  (local $2 i32)
  (local.set $1
   (global.get $global$1)
  )
  (if
   (i32.lt_u
    (local.tee $2
     (i32.and
      (i32.add
       (i32.add
        (local.get $1)
        (local.get $0)
       )
       (i32.const 7)
      )
      (i32.const -8)
     )
    )
    (local.get $1)
   )
   (then
    (unreachable)
   )
  )
  (if
   (i32.gt_u
    (local.get $2)
    (i32.shl
     (memory.size)
     (i32.const 16)
    )
   )
   (then
    (if
     (i32.eq
      (memory.grow
       (i32.sub
        (i32.add
         (i32.shr_u
          (local.get $2)
          (i32.const 16)
         )
         (i32.eqz
          (i32.eqz
           (i32.and
            (local.get $2)
            (i32.const 65535)
           )
          )
         )
        )
        (memory.size)
       )
      )
      (i32.const -1)
     )
     (then
      (unreachable)
     )
    )
   )
  )
  (global.set $global$1
   (local.get $2)
  )
  (local.get $1)
 )
 (func $4 (param $0 f64) (result i64)
  (local $1 i64)
  (local $2 i64)
  (local $3 i64)
  (local $4 i32)
  (local.set $1
   (i64.reinterpret_f64
    (local.get $0)
   )
  )
  (local.set $4
   (i32.sub
    (i32.wrap_i64
     (i64.and
      (i64.shr_u
       (local.get $1)
       (i64.const 52)
      )
      (i64.const 2047)
     )
    )
    (i32.const 1023)
   )
  )
  (if (result i64)
   (i32.or
    (i32.lt_s
     (local.get $4)
     (i32.const 0)
    )
    (i32.ge_s
     (local.get $4)
     (i32.const 116)
    )
   )
   (then
    (i64.const 0)
   )
   (else
    (local.set $2
     (i64.or
      (i64.and
       (local.get $1)
       (i64.const 4503599627370495)
      )
      (i64.const 4503599627370496)
     )
    )
    (local.set $3
     (if (result i64)
      (i32.lt_s
       (local.get $4)
       (i32.const 52)
      )
      (then
       (i64.shr_u
        (local.get $2)
        (i64.extend_i32_u
         (i32.sub
          (i32.const 52)
          (local.get $4)
         )
        )
       )
      )
      (else
       (i64.shl
        (local.get $2)
        (i64.extend_i32_u
         (i32.sub
          (local.get $4)
          (i32.const 52)
         )
        )
       )
      )
     )
    )
    (if (result i64)
     (i64.lt_s
      (local.get $1)
      (i64.const 0)
     )
     (then
      (i64.sub
       (i64.const 0)
       (local.get $3)
      )
     )
     (else
      (local.get $3)
     )
    )
   )
  )
 )
 (func $5 (param $0 i32) (result i32)
  (local $1 i32)
  (if
   (i32.or
    (i32.lt_u
     (local.get $0)
     (global.get $global$7)
    )
    (i32.ge_u
     (local.get $0)
     (global.get $global$6)
    )
   )
   (then
    (return
     (local.get $0)
    )
   )
  )
  (local.set $1
   (global.get $global$5)
  )
  (block $block
   (loop $label
    (br_if $block
     (i32.eqz
      (local.get $1)
     )
    )
    (if
     (i32.and
      (i32.ge_u
       (local.get $0)
       (i32.load offset=4
        (local.get $1)
       )
      )
      (i32.lt_u
       (local.get $0)
       (i32.load offset=8
        (local.get $1)
       )
      )
     )
     (then
      (local.set $0
       (i32.add
        (i32.sub
         (local.get $0)
         (i32.load offset=4
          (local.get $1)
         )
        )
        (i32.load offset=12
         (local.get $1)
        )
       )
      )
      (local.set $1
       (global.get $global$5)
      )
     )
     (else
      (local.set $1
       (i32.load
        (local.get $1)
       )
      )
     )
    )
    (br $label)
   )
  )
  (local.get $0)
 )
 (func $6 (param $0 i32) (param $1 i32) (param $2 i32) (param $3 i32) (param $4 f64) (param $5 f64) (result i64)
  (call $0
   (local.get $1)
   (local.get $2)
   (local.get $3)
   (local.get $4)
   (local.get $5)
  )
 )
 (func $7 (param $0 i32)
  (call $1)
 )
)
