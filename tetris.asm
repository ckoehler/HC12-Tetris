===========
= Display =
===========
16 bit width, 32 bit height
value 1 for block, value 0 for empty

 ==============
 = Event Loop =
 ==============



 =========
 = Moves =
 =========
 Use interrupt
 
1. check collision
1.T move piece
1.F ignore input

2. Check full row
2.T remove line, shift everything above down
2.F continue

3. Reset timer

 =========
 = Timer =
 =========
Every n seconds, shift current piece down by 1.

1. Check collision downward
1.T done with this piece, start over with new piece
1.F move down by 1

 ==========
 = Pieces =
 ==========
 1. Block
 2. L
 3. T
 4. Z
 5. Inverse Z
 6. Line