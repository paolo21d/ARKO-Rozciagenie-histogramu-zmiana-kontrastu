#################################### Rozciaganie histogramu & zmiana kontrastu
.data
	.eqv inputLen 127
	.eqv bufferLen 4000
	.eqv pixelQuant 1000
	str1: .asciiz "Podaj 1 (rozciaganie histogramu) lub 2 (zmiana kontrastu)\n"
	str2: .asciiz "Podaj wspolczynnik zmiany kontrastu przemozony przez 100 np: jesli chcesz podac 0.95->95\n"
	str3: .asciiz "Podaj nazwe obrazka (wraz z rozszerzeniem) do przetwarzania (32bit bitmap). Np: grafika1.bmp\n"
	str4: .asciiz "Blad otworzenia pliku, nie mozna znalezc pliku o nazwie: "
	str5: .asciiz "Blad formatu pliku bmp\n"
	debug1: .asciiz "Szukam min/max\n"
	debug2: .asciiz "Licze tablice LUT\n"
	debug3: .asciiz "Konwertuje pixele\n"
	outFile: .asciiz "result.bmp"
	#outFileC: .asciiz "resultKontrast.bmp"
	.align 2
	imgName: .space inputLen
	.align 2
	buffer: .space bufferLen
	lutB: .space 256
	lutG: .space 256
	lutR: .space 256
	lutA: .space 256
	lut: .space 256
	lutSafe: .space 256 #odwzorowanie 1-1
	minMaxTable: .space 8 #Bmin, Bmax, Gmin, Gmax, Rmin, Rmax, Amin, Amax
	wspKontr: .space 4 #wspolczynnik zmiany kontrastu (niecalokowty) <<6
	wybranaOpcja: .space 4 #1-histogram, 2-kontrast
	
.text #$s0 - deskryptor pliku in; $s1 - width; $s2 - height;  $s3 - offest danych; $s4 - ilosc pixeli; $s7 - deskryptor pliku out
main: 
	#wybor funkcji
	li $v0, 4
	la $a0, str1
	syscall
	li $v0, 5
	syscall
	move $t9, $v0
	sb $t9, wybranaOpcja
	
	#wczytanie nazwy obrazka
	li $v0, 4
	la $a0, str3
	syscall
	li $v0, 8
	la $a0, imgName
	li $a1, inputLen
	syscall
	#usuniecia z tego napisu znaku konca linii
	la $t1, imgName
deleteEndLine:
	lb $t0, ($t1)
	beq $t0, '\n', deleteEndLine_end
	addiu $t1, $t1, 1
	j deleteEndLine
deleteEndLine_end:
	sb $zero, ($t1)
	
	##################################jesli kontrast to wczytanie wspolczynika inaczej jump openFile
	beq $t9, 1, openFile
	li $v0, 4
	la $a0, str2
	syscall
	li $v0, 5
	syscall
	move $s6, $v0
	sll $s6, $s6, 12
	li $t0, 100
	sll $t0, $t0, 6
	div $t8, $s6, $t0 # t8 = wspolczynik <<6 (niecalkowity)
	sw $t8, wspKontr($zero)
	
openFile:
	#otworzenie pliku w trybie do odczytu
	li $v0, 13
	la $a0, imgName
	li $a1, 0
	li $a2, 0
	syscall
	move $s0, $v0 #$s0 - deskryptor pliku in
	blt $s0, 0, fileOpenError
	#otworzenie pliku do zapisu
	li $v0, 13
	la $a0, outFile
	li $a1, 1
	li $a2, 0
	syscall
	move $s7, $v0 #$s7 - deskryptor pliku out
	
	#analiza poczatku naglowka - 2bjatow
	li $v0, 14
	move $a0, $s0
	la $a1, buffer
	li $a2, 2
	syscall 
	la $t1, buffer
	lb $t0, 0($t1)
	bne $t0, 'B', fileFormatError
	lb $t0, 1($t1)
	bne $t0, 'M', fileFormatError
	li $v0, 15
	move $a0, $s7
	la $a1, buffer
	li $a2, 2
	syscall
	
	#analiza reszty naglowka; odczyt offestu, szerokosci, wysokosci
	li $v0, 14
	move $a0, $s0
	la $a1, buffer
	li $a2, 52
	syscall #wczytalismy juz 54bajty
	li $v0, 15
	move $a0, $s7
	la $a1, buffer
	li $a2, 52
	syscall
	la $t1, buffer
	lw $s3, 8($t1)
	lw $s1, 16($t1) #wczytanie width
	lw $s2, 20($t1) #wczytanie height
		
	#wczytanie reszty naglowka, az do poczatku danych
	subiu $t0, $s3, 54
	li $v0, 14
	move $a0, $s0
	la $a1, buffer
	move $a2, $t0
	syscall
	li $v0, 15
	move $a0, $s7
	la $a1, buffer
	move $a2, $t0
	syscall
	
	#ilosc pixeli
	multu $s1, $s2
	mflo $s4
	
	#wypisanie
	li $v0, 1
	move $a0, $s3
	syscall
	li $v0, 11
	li $a0, '\n'
	syscall
	li $v0, 1
	move $a0, $s1
	syscall
	li $v0, 11
	li $a0, '\n'
	syscall
	li $v0, 1
	move $a0, $s2
	syscall
	li $v0, 11
	li $a0, '\n'
	syscall
	li $v0, 1
	move $a0, $s4
	syscall
	li $v0, 11
	li $a0, '\n'
	syscall
	
	#####################wybor sciezki - histogram VS kontrast
	beq $t9, 2, kontrast
###########################################################	histogram: findMaxMin, wypisanieMinMax, createLutHistogram
	li $v0, 4
	la $a0, debug1
	syscall
	li $t9, 0
	li $t1, 255 #B min
	li $t2, 0 #B max
	li $t3, 255 #G min
	li $t4, 0 #G max
	li $t5, 255 #R min
	li $t6, 0 #R max
	li $t7, 255 #A min
	li $t8, 0 #A max
findMinMax: #znalezienie min i max rgba
	bge $t9, $s4, findMinMax_end
	li $v0, 14
	move $a0, $s0
	la $a1, buffer
	li $a2, bufferLen
	syscall
	
	li $s5, 0
	la $s6, buffer
findMinMaxPixel: 
	bge $s5, pixelQuant, findMinMax
	bge $t9, $s4, findMinMax_end
	
	lb $t0, 0($s6) #B
	andi $t0, $t0, 0x0000ff
	ble $t0, $t2, Bmax
	move $t2, $t0
	Bmax:
	bge $t0, $t1, Bmin
	move $t1, $t0
	Bmin:
	
	lb $t0, 1($s6) #G
	andi $t0, $t0, 0x0000ff
	ble $t0, $t4, Gmax
	move $t4, $t0
	Gmax:
	bge $t0, $t3, Gmin
	move $t3, $t0
	Gmin:
	
	lb $t0, 2($s6) #R
	andi $t0, $t0, 0x0000ff
	ble $t0, $t6, Rmax
	move $t6, $t0
	Rmax:
	bge $t0, $t5, Rmin
	move $t5, $t0
	Rmin:
	
	lb $t0, 3($s6) #A
	andi $t0, $t0, 0x0000ff
	ble $t0, $t8, Amax
	move $t8, $t0
	Amax:
	bge $t0, $t7, Amin
	move $t7, $t0
	Amin:
	
	addiu $t9, $t9, 1
	addiu $s5, $s5, 1
	addiu $s6, $s6, 4
	j findMinMaxPixel
findMinMaxPixel_end: 
	j findMinMaxPixel
findMinMax_end:
	#zapisanie wartosci min/max do minMaxTable
	la $t9, minMaxTable
	sb $t1, 0($t9)
	sb $t2, 1($t9)
	sb $t3, 2($t9)
	sb $t4, 3($t9)
	sb $t5, 4($t9)
	sb $t6, 5($t9)
	sb $t7, 6($t9)
	sb $t8, 7($t9)
	#wypisanie wartosci min/max RGB
	li $v0, 11
	li $a0, 'R'
	syscall
	li $v0, 1
	move $a0, $t5
	syscall
	li $v0, 11
	li $a0, ' '
	syscall
	li $v0, 1
	move $a0, $t6
	syscall
	li $v0, 11
	li $a0, '\n'
	syscall
	
	li $v0, 11
	li $a0, 'G'
	syscall
	li $v0, 1
	move $a0, $t3
	syscall
	li $v0, 11
	li $a0, ' '
	syscall
	li $v0, 1
	move $a0, $t4
	syscall
	li $v0, 11
	li $a0, '\n'
	syscall
	
	li $v0, 11
	li $a0, 'B'
	syscall
	li $v0, 1
	move $a0, $t1
	syscall
	li $v0, 11
	li $a0, ' '
	syscall
	li $v0, 1
	move $a0, $t2
	syscall
	li $v0, 11
	li $a0, '\n'
	syscall
	
	li $v0, 11
	li $a0, 'A'
	syscall
	li $v0, 1
	move $a0, $t7
	syscall
	li $v0, 11
	li $a0, ' '
	syscall
	li $v0, 1
	move $a0, $t8
	syscall
	li $v0, 11
	li $a0, '\n'
	syscall
	
	############################### createLutHistogram
	li $v0, 4
	la $a0, debug2
	syscall
	
	######napisac createLutHistogram
	li $t9, 0
	la $t8, minMaxTable
createLutHistogram:
	beq $t9, 256, createLutHistogram_end
	li $t7, 0
	la $t8, lutB
	addu $t8, $t8, $t9 #wskazanie w tablicy lut BGRA
	
	createIN:
	beq $t7, 8, createIN_end
	lb $t1, minMaxTable($t7) #min
	andi $t1, $t1, 0x000000ff
	addiu $t7, $t7, 1
	lb $t2, minMaxTable($t7) #max
	andi $t2, $t2, 0x000000ff
	
	subu $s6, $t2, $t1 # max-min
	sll $s6, $s6, 6 # max-min <<6
	li $s5, 255
	sll $s5, $s5, 12 # 255 <<12
	div $s5, $s5, $s6 #s5 = 255/(max-min) <<6
	
	subu $s6, $t9, $t1 #s6 = i-min
	sll $s6, $s6, 6 #s6 = i-min <<6
	mul $s5, $s5, $s6
	mfhi $s6
	sll $s6, $s6, 26
	srl $s5, $s5, 6
	or $s1, $s5, $s6 #s1 = wynik <<6
	srl $s5, $s1, 6 #s5 -> wynik
	#subu $s6, $t9, $t1
	sgt $s6, $t9, $t1
	mul $s5, $s5, $s6
	ble $s5, 255, storeLut
	li $s5, 255
	storeLut:
	
	sb $s5, ($t8)
	
	addiu  $t8, $t8, 256
	addiu $t7, $t7, 1
	j createIN
	createIN_end:
	addiu $t9, $t9, 1
	j createLutHistogram
createLutHistogram_end:
	
	#wypisanie lut
	li $t1, 0
lutShowH:
	beq $t1, 256, lutShowH_end
	li $v0, 1
	move $a0, $t1
	syscall
	li $v0, 11
	li $a0, ' '
	syscall
	lb $a0, lutR($t1)
	andi $a0, $a0, 0x000000ff
	li $v0, 1
	syscall
	li $v0, 11
	li $a0, ' '
	syscall
	lb $a0, lutG($t1)
	andi $a0, $a0, 0x000000ff
	li $v0, 1
	syscall
	li $v0, 11
	li $a0, ' '
	syscall
	lb $a0, lutB($t1)
	andi $a0, $a0, 0x000000ff
	li $v0, 1
	syscall
	li $v0, 11
	li $a0, '\n'
	syscall
	addiu $t1, $t1, 1
	j lutShowH
lutShowH_end:
	la $t2, lutB
	la $t3, lutG
	la $t4, lutR
	#la $t5, lutA
	la $t5, lutSafe
	j changePixels
###########################################################		
###########################################################	kontrast: createLutContrast
###########################################################	
kontrast:
	
#Create LUT tables CONTRAST
	li $v0, 4
	la $a0, debug2
	syscall
	li $t9, 0 #licznik do 255
createLutContrast:
	beq $t9, 256, createLutContrast_end
	li $t7, 255 #max
	sll $t7, $t7, 5 # t7 = max/2 <<6
	move $s5, $t9
	sll $s5, $s5, 6
	sub $s5, $s5, $t7 # i - max/2 <<6
	mul $s5, $s5, $t8
	mfhi $s6
	sll $s6, $s6, 26
	sra $s5, $s5, 6
	or $s5, $s5, $s6 # a*(i-max/2) <<6
	add $s5, $s5, $t7 # a*(i-max/2) + max/2 <<6
	sra $s5, $s5, 6
	
	#sgt $s1, $s5, 255
	#slt $s2, $s5, 0
	#or $s6, $s1, $s2
	
	bgt $s5, 255, set255c
	blt $s5, 0, set0c
	j storec
	set255c: 
	li $s5, 255
	j storec
	set0c: 
	li $s5, 0
	
	storec:
	
	sb $s5, lut($t9)
	addiu $t9, $t9, 1
	j createLutContrast
createLutContrast_end:

	#wypisanie lut
	li $t1, 0
lutShowC:
	beq $t1, 256, lutShowC_end
	li $v0, 1
	move $a0, $t1
	syscall
	li $v0, 11
	li $a0, ' '
	syscall
	lb $a0, lut($t1)
	andi $a0, $a0, 0x000000ff
	li $v0, 1
	syscall
	li $v0, 11
	li $a0, '\n'
	syscall
	addiu $t1, $t1, 1
	j lutShowC
lutShowC_end:
#	li $t2, 0
#createSafeLut:
#	sb $t2, lutSafe($t2)
#	addiu $t2, $t2, 1
#	bne $t2, 257, createSafeLut
	la $t2, lut
	la $t3, lut
	la $t4, lut
	la $t5, lutSafe

	############################################################################ podamiana pixeli
	############################################################################
changePixels: 
	li $v0, 4
	la $a0, debug3
	syscall
	li $v0, 16
	move $a0, $s0
	syscall
	li $v0, 13
	la $a0, imgName
	li $a1, 0
	li $a2, 0
	syscall
	move $s0, $v0 #$s0 - deskryptor pliku in
	blt $s0, 0, fileOpenError
	#wyczttanie calej ramki az do poczatku danych
	li $v0, 14
	move $a0, $s0
	la $a1, buffer
	move $a2, $s3
	syscall
			
	li $t9, 0
createSafeLut:
	sb $t9, lutSafe($t9)
	addiu $t9, $t9, 1
	bne $t9, 257, createSafeLut
		
	li $t9, 0
	li $t0, 0
	#t2=lutB, t3=lutG, t4=lutR, t5=lutA - adresy
save:
	bge $t9, $s4, save_end
	li $v0, 14
	move $a0, $s0
	la $a1, buffer
	li $a2, bufferLen
	syscall
	
	li $s5, 0
	la $s6, buffer
saveIn:
	bge $s5, pixelQuant, saveIn_end
	bge $t9, $s4, saveIn_end
	
	lb $t0, 0($s6) #B
	andi $t0, $t0, 0x0000ff
	addu $t0, $t0, $t2
	lb $t1, ($t0)
	andi $t1, $t1, 0x0000ff
	sb $t1, 0($s6)
	
	lb $t0, 1($s6) #G
	andi $t0, $t0, 0x0000ff
	addu $t0, $t0, $t3
	lb $t1, ($t0)
	andi $t1, $t1, 0x0000ff
	sb $t1, 1($s6)
	
	lb $t0, 2($s6) #R
	andi $t0, $t0, 0x0000ff
	addu $t0, $t0, $t4
	lb $t1, ($t0)
	andi $t1, $t1, 0x0000ff
	sb $t1, 2($s6)
	
	lb $t0, 3($s6) #A
	andi $t0, $t0, 0x0000ff
	addu $t0, $t0, $t5
	lb $t1, ($t0)
	andi $t1, $t1, 0x0000ff
	sb $t1, 3($s6)

	addiu $t9, $t9, 1
	addiu $s5, $s5, 1
	addiu $s6, $s6, 4
	j saveIn
saveIn_end:
	li $v0, 15
	move $a0, $s7
	la $a1, buffer
	li $a2, bufferLen
	syscall
	j save
save_end:
	############################################################################ CloseFile and Finish Program
closeFiles:
	#close file in
	li $v0, 16
	move $a0, $s0
	syscall
	#close file out
	li $v0, 16
	move $a0, $s7
	syscall
	
	li $v0, 10
	syscall
	##################################### KONIEC PROGRAMU
fileOpenError:
	li $v0, 4
	la $a0, str4
	syscall
	li $v0, 4
	la $a0, imgName
	syscall
	li $v0, 10
	syscall
fileFormatError:
	li $v0, 4
	la $a0, str5
	syscall
	li $v0, 10
	syscall
