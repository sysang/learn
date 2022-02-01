;
; gram-class-api.scm
;
; Representing word-classes as vectors of (pseudo-)connector-sets.
;
; Copyright (c) 2017, 2019 Linas Vepstas
;
; ---------------------------------------------------------------------
; OVERVIEW
; --------
; This file provides the `matrix-object` API that allows grammatical
; classes of words to be treated as vectors of connector-sets (vectors
; of disjuncts; vectors of Sections).
;
; This is meant to be used as a wrapper around `make-pseudo-cset-api`,
; extending it so that both `WordNode`s and `WordClassNode`s are handled.
;
; ---------------------------------------------------------------------
;
(use-modules (srfi srfi-1))
(use-modules (opencog))
(use-modules (opencog persist))
(use-modules (opencog matrix))

; ---------------------------------------------------------------------

; This class kind-of resembles a direct sum (as coded in the
; `direct-sum` object) but its ad hoc, hard-coded, not generic.
(define-public (add-gram-class-api LLOBJ)
"
  add-gram-class-api LLOBJ -- Enable (WordClass, disjunct) pairs.

  This will take LLOBJ and extend it's native `left-type with the
  `WordClass` type, so that the left type can be either.  It also
  provides methods for managing the `MemberLink`s that indicate
  membership of the 'left-type in the `WordClass`.

  The membership of a word to a WordClass is denoted as

      (MemberLink (WordNode \"foo\") (WordClassNode \"bar\"))

  Keep in mind that a word might belong to more than one WordClass.
  Contributions to the class are stored as counts on the MemberLink.

  See the `pseudo-csets.scm` file for a general overview.

  Provided methods:
    'left-type -- returns (TypeChoice (LLOBJ 'left-type) (Type 'WordClassNode))
    'store-aux -- Store the MemberLinks above.
    'fetch-pairs -- Fetch both WordClassNodes and MemberLinks.

    'cluster-type -- returns (Type 'WordClassNode)

    'make-cluster WA WB -- Creates a WordClassNode
"
	(define (get-left-type)
		(TypeChoice (LLOBJ 'left-type) (Type 'WordClassNode)))

	(define any-left (AnyNode "gram-class"))
	(define (get-left-wildcard DJ) (ListLink any-left DJ))

	; Recycle the right wildcard from the parent class.
	; XXX FIXME: this won't work for some classes, which store
	; marginals in a different format than pairs. That is, the
	; 'right-element method will work correctly on pairs only,
	; not on marginals. For example, direct-sum is like that.
	; Perhaps we should blame the classes for mis-handling marginals?
	(define any-right (LLOBJ 'right-element (LLOBJ 'wild-wild)))
	(define (get-wild-wild) (ListLink any-left any-right))

	; Fetch (from the database) all Sections that have a WordClass
	; on the left-hand-side. Fetch the marginals, too.
	(define (fetch-disjuncts)

		; Let the base object do the heavy lifting.
		(LLOBJ 'fetch-pairs)

		(define start-time (current-time))

		; Fetch all MemberLinks, as these indicate which Words
		; belong to which WordClasses. Sections have already been
		; fetched by the LLOBJ, so we won't do anything more, here.
		(load-atoms-of-type 'WordClassNode)
		(for-each
			(lambda (wcl)
				(fetch-incoming-by-type wcl 'MemberLink))
			(cog-get-atoms 'WordClassNode))

		; Load marginals, too. These are specific to this class.
		(fetch-incoming-set any-left)

		(format #t "Elapsed time to load grammatical classes: ~A secs\n"
			(- (current-time) start-time)))

	; Store into the database the "auxiliary" MemberLinks between
	; WordClassNodes and WordNodes. Without this, the dataset is
	; incomplete.
	(define (store-aux)
		(for-each
			; lambda over lists of MemberLink's
			(lambda (memb-list)
				(for-each
					; lambda over MemberLinks
					(lambda (memb)
						; If the right kind of MemberLink
						(if (eq? 'WordNode (cog-type (gar memb)))
							(store-atom memb)))
					memb-list))
			; Get all MemberLinks that this WordClass belongs to.
			(map (lambda (wrdcls) (cog-incoming-by-type wrdcls 'MemberLink))
				(cog-get-atoms 'WordClassNode))))

	;-------------------------------------------
	; Custom methods specific to this object.
	(define (get-cluster-type) (Type 'WordClassNode))

	; Create a word-class out of two words, or just extend an
	; existing word class. Here, "extend" means "do nothing",
	; return the existing class. If this is called a second time
	; with the same arguments, then a new, unique name is generated!
	; Therefore, this should never be called than once!
	; XXX FIXME the semantics of this thing is ugly, and should be
	; moved to the caller. We shouldn't have to second-guess the
	; callers dsired behavior!
	(define (make-cluster A-ATOM B-ATOM)
		(define is-a-class (eq? 'WordClassNode (cog-type A-ATOM)))
		(define is-b-class (eq? 'WordClassNode (cog-type B-ATOM)))
		(cond
			(is-a-class A-ATOM)
			(is-b-class B-ATOM)
			(else (let
					((cluname (string-join
						(list (cog-name A-ATOM) (cog-name B-ATOM)))))

				; If `cluname` already exists, then append "(dup)" to the
				; end of it, and try again. Keep repeating. In the real
				; world, this should never happen more than once, maybe
				; twice, unimaginable three times. So that iota is safe.
				(every
					(lambda (N)
						(if (nil? (cog-node 'WordClassNode cluname)) #f
							(begin
								(set! cluname (string-append cluname " (dup)"))
								#t)))
					(iota 10000))
				(WordClassNode cluname)))))

	;-------------------------------------------
	(define (describe)
		(display (procedure-property add-gram-class-api 'documentation)))

	;-------------------------------------------
	; Explain the non-default provided methods.
	(define (provides meth)
		(case meth
			((left-type)        get-left-type)
			((store-aux)        store-aux)
			(else #f)
	))

	; Methods on the object
	(lambda (message . args)
		(apply (case message
			((name)           (lambda () "WordClass-Disjunct Pairs"))
			((id)             (lambda () "gram-class"))
			((left-type)      get-left-type)
			((left-wildcard)  get-left-wildcard)
			((wild-wild)      get-wild-wild)

			((fetch-pairs)    fetch-disjuncts)
			((store-aux)      store-aux)

			((cluster-type)   get-cluster-type)
			((make-cluster)   make-cluster)

			((provides)       provides)
			((filters?)       (lambda () #f))
			((describe)       describe)
			((help)           describe)
			((obj)            (lambda () "add-gram-class-api"))
			((base)           (lambda () LLOBJ))
			(else             (lambda ( . rest ) (apply LLOBJ (cons message args))))
		) args))
)

; ---------------------------------------------------------------------

(define-public (add-singleton-classes LLOBJ)
"
  add-singleton-classes LLOBJ -- manage singleton WordClassNodes

  After clustering, there will still be many WordNodes that have not
  been assigned to clusters. This may be the case for three reasons:
   * The Wordnode really is in a class of it's own.
   * The clustering algo has not gotten around to it yet.
   * It is rare, infrequently-observed junk.
  This object provides management callbacks to place some words into
  singleton WordClassNodes, based on their count or relative rank.

  Note that using this object will cause the MI values between
  word-classes and disjuncts to become invalid; if these are needed,
  then they will need to be recomputed.

  Provided methods:
     'delete-singles -- Remove all WordClassNodes that have only a
           single member.

     'create-singles LIST -- Create a WordClassNode for each WordNode
           in the LIST. The complete set of Sections will be copied
           from the WordNode to the WordClassNode; the values on the
           Section will be copied as well, so that the Sections have
           correct counts on them.

     'create-hi-count-singles MIN-CUTOFF -- Create a WordClassNode for
           each WordNode whose observation count is greater than
           MIN-CUTOFF. As above, Sections and values are copied.

     'create-top-rank-singles NUM -- Create a WordClassNode for the
           top-ranked NUM WordNode's having the highest observation
           counts.  As above, Sections and values are copied.

  Known bugs:
  * delete-singles is broken
"
	(if (not (LLOBJ 'provides 'flatten))
		(throw 'missing-method 'add-singleton-classes
			"The 'flatten method is needed to create singletons"))

	; XXX this is broken
	(define (delete-singles)
		; delete each word-class node..
		(throw 'not-implemented 'add-singleton-classes
			"This method is borken and don't work right!")
		(for-each cog-delete-recursive!
			; make a list of word-classes containing only one word...
			(filter
				(lambda (WRDCLS)
					(eq? 1 (cog-incoming-size-by-type WRDCLS 'MemberLink)))
				(LLOBJ 'left-basis))))

	; Need to fetch the count from the margin.
	(define pss (add-support-api LLOBJ))

	; Create singletons
	(define (create-singles WORD-LIST)
		; Copy the count-value, and anything else.
		(define (copy-values NEW OLD)
			(for-each
				(lambda (KEY)
					(cog-set-value! NEW KEY (cog-value OLD KEY)))
				(cog-keys OLD)))

		(define start-time (current-time))

		(for-each
			(lambda (WRD)
				(define wcl (WordClass (string-append (cog-name WRD) "#uni")))
				; Add the word to the new word-class (obviously)
				(define memb (MemberLink WRD wcl))
				(cog-inc-count! memb (pss 'right-count WRD))
				(store-atom memb)

				; Copy the sections
				(for-each
					(lambda (PNT)
						(copy-values (LLOBJ 'flatten wcl PNT) PNT)

						; Delete the original section, as otherwise they
						; will disrupt the marginals.
						(cog-delete! PNT)
					)
					(LLOBJ 'right-stars WRD)))
			WORD-LIST)

		(format #t "Created ~A singleton word classes in ~A secs\n"
			(length WORD-LIST) (- (current-time) start-time))

		(LLOBJ 'clobber)
	)

	; Create singletons for those words with more than MIN-CNT
	; observations.
	(define (trim-low-counts MIN-CNT)

		(define trimmed-words
			(remove (lambda (WRD)
				(or
					(equal? 'WordClassNode (cog-type WRD))
					(< (pss 'right-count WRD) MIN-CNT)))
				(LLOBJ 'left-basis)))

		(format #t "After trimming, ~A words left, out of ~A\n"
			(length trimmed-words) (LLOBJ 'left-basis-size))

		(create-singles trimmed-words)
	)

	; Create singletons for top-ranked words.
	(define (top-ranked NUM-TOP)

		; nobs == number of observations
		(define (nobs WRD) (pss 'right-count WRD))

		(define words-only
			(remove
				(lambda (WRD) (equal? 'WordClassNode (cog-type WRD)))
				(LLOBJ 'left-basis)))

		(define ranked-words
			(sort! words-only
				(lambda (ATOM-A ATOM-B) (> (nobs ATOM-A) (nobs ATOM-B)))))

		(define short-list (take ranked-words NUM-TOP))

		(format #t "After sorting, kept ~A words out of ~A\n"
			(length short-list) (LLOBJ 'left-basis-size))

		(create-singles short-list)
	)

	; Methods on the object
	(lambda (message . args)
		(case message
			((delete-singles) (delete-singles))
			((create-singles) (apply create-singles args))
			((create-hi-count-singles) (apply trim-low-counts args))
			((create-top-rank-singles) (apply top-ranked args))
			(else             (apply LLOBJ (cons message args)))
		))
)

; ---------------------------------------------------------------------
; The next three routines are used to build a cached set of valid
; connector-seqs, for the right-basis-pred.
; We need to know if every connector in a connector sequence is
; a member of some word in WORD-LIST. Verifying this directly is
; very inefficient. It is much faster to precompute the set of
; known-good connector sequences, and refer to that.

(define (get-connectors WRD-LST)
"
  Return a list of connectors containing a word in the list
"
	(define con-set (make-atom-set))
	(for-each
		(lambda (word)
			(for-each con-set
				(cog-incoming-by-type word 'Connector)))
		WRD-LST)
	(con-set #f)
)

;-----------------------------
(define (get-con-seqs CON-LST)
"
  Return a list of ConnectorSeq containing one or more
  connectors from the CON-LST
"
	(define seq-set (make-atom-set))
	(for-each
		(lambda (ctr)
			(for-each seq-set
				(cog-incoming-by-type ctr 'ConnectorSeq)))
		CON-LST)
	(seq-set #f)
)

;-----------------------------
(define (make-conseq-predicate STAR-OBJ WORD-LIST-FUNC)
"
  make-conseq-predicate STAR-OBJ WORD-LIST-FUNC - connector predicate

  Create a predicate that returns true when a given ConnectorSeq
  consists of WordNodes entirely in teh given word-list returned from
  WORD-LIST-FUNC.

  That is, WORD-LIST-FUNC, when called, should return a list of words.
  This function will then return a predicate for identifying connector
  sequences consisting entirely of words in that word-list.

  This may take a few minutes to run, if there are millions of
  ConnectorSeq's.

  XXX Fixme: what about connector seqs containing WordClases?
"
	(define all-words
		(filter (lambda (ITEM) (equal? (cog-type ITEM) 'WordNode))
			(STAR-OBJ 'left-basis)))

	; Unwanted words are not part of the matrix.
	(define unwanted-words
		(atoms-subtract all-words (WORD-LIST-FUNC)))

	(define unwanted-cnctrs
		(get-connectors unwanted-words))

	(define unwanted-conseqs
		(get-con-seqs unwanted-cnctrs))

	(define good-conseqs
		(atoms-subtract
			; Take all connector-sequences, and subtract the bad ones.
			; (cog-get-atoms 'ConnectorSeq)
			(STAR-OBJ 'right-basis)
			unwanted-conseqs))

	; Return the predicate that returns #t only for good ones.
	(make-aset-predicate good-conseqs)
)

;-----------------------------
(define (add-linking-filter LLOBJ WORD-LIST-FUNC ID-STR RENAME)
"
  add-linking-filter LLOBJ - Filter the word-disjunct LLOBJ so that
  the only connector sequences appearing on the right consist entirely
  of connectors that have words appearing in the WORD-LIST. This is
  not a public function; it is used to build several public functions.
"
	(define star-obj (add-pair-stars LLOBJ))

	; Always keep any WordNode or WordClassNode we are presented with.
	(define (left-basis-pred WRDCLS) #t)

	(define ok-conseq? #f)

	; Only accept a ConnectorSeq if every word in every connector
	; is in some word-class.
	(define (right-basis-pred CONSEQ)
		(if (not ok-conseq?)
			(set! ok-conseq? (make-conseq-predicate star-obj WORD-LIST-FUNC)))
		(ok-conseq? CONSEQ)
	)

	; Input arg is a Section. The gdr (right hand side of it) is a
	; conseq. Keep the section if the conseq passes.
	(define (pair-pred SECT) (right-basis-pred (gdr SECT)))

	; ---------------
	(add-generic-filter LLOBJ
		left-basis-pred right-basis-pred pair-pred ID-STR RENAME)
)

;-----------------------------
(define (linking-trim LLOBJ WORD-LIST-FUNC)
"
  linking-trim LLOBJ - Trim the word-disjunct LLOBJ by deleting words
  and connector sequences and sections which contain words other than
  those provided by the WORD-LIST-FUNC. This is like `add-linking-filter`
  above, except that it doesn't filter, it just deletes.  This is
  not a public function; it is used to build several public functions.
"
	(define star-obj (add-pair-stars LLOBJ))

	; Always keep any WordNode or WordClassNode we are presented with.
	(define (left-basis-pred WRDCLS) #t)

	(define ok-conseq? #f)

	; Only accept a ConnectorSeq if every word in every connector
	; is in some word-class.
	(define (right-basis-pred CONSEQ)
		(if (not ok-conseq?)
			(set! ok-conseq? (make-conseq-predicate star-obj WORD-LIST-FUNC)))
		(ok-conseq? CONSEQ)
	)

	; Input arg is a Section. The gdr (right hand side of it) is a
	; conseq. Keep the section if the conseq passes.
	(define (pair-pred SECT) (right-basis-pred (gdr SECT)))

	; ---------------
	(define trim-mtrx (add-trimmer LLOBJ))
	(trim-mtrx 'generic-trim left-basis-pred right-basis-pred pair-pred)
)

; ---------------------------------------------------------------------

(define-public (add-wordclass-filter LLOBJ RENAME)
"
  add-wordclass-filter LLOBJ - Modify the wordclass-disjunct LLOBJ so
  that the only connector sequences appearing on the right consist
  entirely of connectors that have words in word-classes appearing on
  the left. The resulting collection of wordclass-disjunct pairs is
  then self-consistent, and does not contain any connectors unable to
  form a connection to some word-class.

  Set RENAME to #t if marginals should be stored under a filter-specific
  name. Otherwise, set to #f to use the default marginal locations.
"
	; Return a list of words in word-classes
	(define (get-wordclass-words)
		(define word-set (make-atom-set))
		(for-each
			(lambda (wcls)
				(word-set wcls)
				(for-each word-set
					(map gar (cog-incoming-by-type wcls 'MemberLink))))

			; XXX FIXME: ask LLOBJ for the classes.
			(cog-get-atoms 'WordClassNode))
		(word-set #f))

	(define id-str "wordclass-filter")

	(add-linking-filter LLOBJ get-wordclass-words id-str RENAME)
)

; ---------------------------------------------------------------------

(define-public (add-linkage-filter LLOBJ RENAME)
"
  add-linkage-filter LLOBJ - Modify the word-disjunct LLOBJ so that
  the only connector sequences appearing on the right consist entirely
  of connectors that have words appearing on the left. The resulting
  collection of word-disjunct pairs is then mostly self-consistent,
  in that it does not contain any connectors unable to form a
  connection to some word.  However, it may still contain words on
  the left that do not appear in any connectors!

  Set RENAME to #t if marginals should be stored under a filter-specific
  name. Otherwise, set to #f to use the default marginal locations.
"
	(define star-obj (add-pair-stars LLOBJ))

	; Return a list of words
	(define (get-words) (star-obj 'left-basis))

	(define id-str "linkage-filter")

	(add-linking-filter LLOBJ get-words id-str RENAME)
)

; ---------------------------------------------------------------------

(define-public (trim-linkage LLOBJ)
"
  trim-linkage LLOBJ - Trim the word-disjunct LLOBJ by deleting words
  and connector sequences and sections which contain words other than
  those appearing in the left-basis.  This is like `add-linkage-filter`,
  except that it doesn't filter, it just deletes.  The resulting
  collection of word-disjunct pairs is then self-consistent,
  in that it does not contain any connectors unable to form a
  connection to some word.
"
	(define star-obj (add-pair-stars LLOBJ))

	; Return a list of words
	(define (get-words) (star-obj 'left-basis))

	(define id-str "linkage-filter")

	(linking-trim LLOBJ get-words)
)

; ---------------------------------------------------------------------
