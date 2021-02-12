;
; gen-dict.scm - Generate a random artificial grammar
;
; The generated dictionary is determined by the parameters in this file.
;
(use-modules (opencog) (opencog nlp fake))

; Number of Link Grammar link types (connector types)
(define num-link-types 6)

; Link-type Zipf distribution exponent. The generated random grammar
; will use different link types with a Zipfian distribution, with this
; exponent. Setting this to 1 gives the classic Zipf distribution, with
; link type "A" being more likely than "B" which is more likely than "C"
; and so on. Setting this to zero gives a uniform random distribution.
(define link-type-exp 1)

; Maximum size of disjuncts; that is, the maximum number of connectors
; in a disjunct. Randomly-created disjuncts will have 1 to this many
; connectors in them. The size distribution is Zipfian, controlled by
; the exponent `disjunct-exp`.
(define max-disjunct-size 3)

; Disjunct-size Zipf distribution exponent. The generated random
; disjunct will be of varying length, with the length following a
; Zipfian distribution. Setting this to 1 gives the classic Zipf
; distribution, so that most disjuncts will be of size 1, a few will
; be size 2, fewer still of size 3, etc. Setting this to zero gives
; a uniform distribution. Setting this negative will make most disjuncts
; have the `max-disjunct-size`.
(define disjunct-exp 0.5)

; Disjuncts per section. Each section will contain up to this many
; different disjuncts. The number of disjuncts per section follows a
; Zipfian distribution, with an exponent of `section-exp`.
(define section-size 20)

; Section-size Zipf distribution exponent. The generated random section
; will have a varying number of disjuncts in it, with the number
; following a Zipfian distribution. Setting this to 1 gives the classic
; Zipf distribution, so that most sections will be have only 1 disjunct
; in them; a few will be size 2, fewer still of size 3, etc. Setting
; this to zero gives a uniform size distribution. Setting this negative
; will make most sections have `section-size` disjuncts in them.
(define section-exp 0.0)

; Number of pos tags
(define num-pos 10)

; Number of grammatical classes
(define num-classes 10)

; Number of pos tags per class
(define class-size 8)

; Exponent of the class-size distribution.
; Setting this to 1.0 gives the classic Zipf distribution;
; setting it to 0.0 gives the uniform distribution.
; Using Zipf means that in most cases, each word class will have only
; one or two pos-tags in it; setting it to uniform means that larger
; classes (largr complexity) will be common. Setting the exponent
; negative will make most classes to be maximal in size, i.e. to have
; to have `class-size` elements.
(define class-exp -0.1)

; Number of synonyms in a word-class
(define num-synonyms 6)

; Exponent of the synonym word-class size distribution.
; Setting this to 1.0 gives the classic Zipf distribution;
; setting it to 0.0 gives the uniform distribution.
; Using Zipf means that in most cases, there will be only one or
; two synonyms; setting it to uniform means that large synonym classes
; will be common. Setting the exponent negative will make most
; synonym clases have the max allowed, i.e. to have `num-synonyms`
; in each one.
(define synonym-exp 0.5)

; Output file
(define dict-file "/tmp/4.0.dict")

; -------------------------------------------
; Generators for each of the different parts of the grammar.

(define posgen
	(create-pos-generator
		num-pos
		num-link-types
		max-disjunct-size
		section-size
		link-type-exp
		disjunct-exp
		section-exp))

(define classgen
	(create-class-generator
		num-classes
		num-pos
		class-size
		class-exp))

(define wordgen
	(create-word-generator
		num-classes
		num-synonyms
		synonym-exp))

(define port (open-file "/tmp/4.0.dict" "w"))

(print-LG-flat port (posgen))
(print-LG-flat port (classgen))
(print-LG-flat port (wordgen))

(close port)
