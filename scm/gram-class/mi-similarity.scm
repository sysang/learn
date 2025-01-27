;
; mi-similarity.scm
;
; Compute MI similarities between word-pairs. Provide lists of
; top-ranked words and word-pairs.
;
; Copyright (c) 2021 Linas Vepstas
;
; ---------------------------------------------------------------------

(use-modules (srfi srfi-1))
(use-modules (ice-9 optargs)) ; for define*-public
(use-modules (opencog) (opencog matrix) (opencog persist))

; ---------------------------------------------------------------

(define (do-add-similarity-api LLOBJ)
"
	do-add-similarity-api LLOBJ -- Return the correct similarity API.
"
	; The SIM-ID is the key under which the actual values are stored.
	(define SIM-ID "shape-mi")
	(add-similarity-api LLOBJ #f SIM-ID))

; ---------------------------------------------------------------

(define-public (rank-words LLOBJ)
"
  rank-words LLOBJ -- Return a list of all words, ranked by count.
  If counts are equal, then rank by support. This may take half-a-
  minute to run.  Assumes that supports have been computed and are
  available.

  Here, a 'word' is any item appearing in the left-basis of LLOBJ.
  Thus, it might include word-classes, not just words.
"
	(define sup (add-support-api LLOBJ))

	; nobs == number of observations
	(define (nobs WRD) (sup 'right-count WRD))
	(define (nsup WRD) (sup 'right-support WRD))

	(define wrds (LLOBJ 'left-basis))
	(sort wrds
		(lambda (ATOM-A ATOM-B)
			(define na (nobs ATOM-A))
			(define nb (nobs ATOM-B))
			(if (equal? na nb)
				(> (nsup ATOM-A) (nsup ATOM-B))
				(> na nb))))
)

; ---------------------------------------------------------------

(define (make-simmer LLOBJ)
"
  make-simmer LLOBJ -- return function that computes and stores MI's.

  This computes and stores both the MI and the Ranked-MI scores.

  The computation is performed unconditionally; a new MI is computed,
  even if there is an existing one cached.
"
	(define sap (do-add-similarity-api LLOBJ))
	(define smi (add-symmetric-mi-compute LLOBJ))

	(define ol2 (/ 1.0 (log 2.0)))
	(define (log2 x) (if (< 0 x) (* (log x) ol2) -inf.0))

	(define mmt-q (smi 'mmt-q))

	; Compute and save both the fmi and the ranked-MI.
	; The marginal is sum_d P(w,d)P(*,d) / sum_d P(*,d)P(*,d)
	; The mmt-q is sum_d P(*,d)P(*,d) =
	;              sum_d N(*,d)N(*,d) / [ sum_d N(*,d) ]^2
	(define (compute-sim WA WB)
		(define fmi (smi 'mmt-fmi WA WB))
		(define mwa (smi 'mmt-marginal WA))
		(define mwb (smi 'mmt-marginal WB))
		(define rmi (+ fmi (* 0.5 (log2 (* mwa mwb))) mmt-q))

		; Print something, so user has something to look at.
		(if (< 6 fmi)
			(format #t "\tMI(`~A`, `~A`) = ~6F  rank-MI = ~6F\n"
				(cog-name WA) (cog-name WB) fmi rmi))
		(store-atom
			(sap 'set-pair-similarity
				(sap 'make-pair WA WB)
				(FloatValue fmi rmi))))

	; Return the function that computes the MI for pairs.
	compute-sim
)

; ---------------------------------------------------------------

(define-public (compute-diag-mi-sims LLOBJ WORDLI START-RANK DEPTH)
"
  compute-diag-mi-sims LLOBJ WORDLI START-RANK DEPTH - compute MI.

  This will compute the MI similarity of words lying around a diagonal.
  The width of the diagonal is DEPTH. The diagonal is defined by the
  the ranked words. Computations start at START-RANK and proceed to
  DEPTH.  If the Similarity has already been recorded, it will not
  be recomputed.

  Think of a tri-diagonal matrix, but instead of three, it is N-diagonal,
  with N given by DEPTH.

  WORDLI is a list of words, presumed sorted by rank, defining the
  diagonal.

  Examples: If START-RANK is 0 and DEPTH is 200, then the 200x200
  block matrix of similarities will be computed. Since similarities
  are symmetric, this is a symmetric matrix, and so 200 x 201 / 2
  grand total similarities are computed. (This is a 'triangle number')

  If START-RANK is 300 and DEPTH is 200, then computations start at
  the 300'th ranked word and continue through the 500'th ranked word.
  This results in a total of 200x200 similarities, as 200 rows are
  computed, out to 200 places away from the diagonal. Visually, this is
  a rhombus, one side lying along the diagonal (a rhombus is a
  parellelogram with all sides equal length.)
"
	; Create a new simmer each time, so we get the updated
	; mmt-q value for this session.
	(define do-compute-sim (make-simmer LLOBJ))

	; Don't recompute similarity, if we've already got it.
	(define sap (do-add-similarity-api LLOBJ))
	(define (compute-sim WA WB)
		(define miv (sap 'pair-count WA WB))
		(if (not miv) (do-compute-sim WA WB)))

	; Perform similarity computations for one row.
	(define (batch-simlist ITEM ITEM-LIST)
		(for-each
			(lambda (item) (compute-sim ITEM item))
			ITEM-LIST))

	; Take the word list and trim it down.
	(define nwords (length WORDLI))
	(define start (min START-RANK nwords))   ; avoid overflow
	(define depth (min DEPTH (- nwords start)))  ; avoid overflow
	(define row-range (take (drop WORDLI start) depth)) ; list of words to do
	(define (col-start off) (max 0 (- (+ start off) depth))) ;  column start
	(define (col-end off) (min (+ start off) depth)) ;  column end
	(define (col-range off)   ; reverse, so we go from diagonal outwards
		(reverse (take (drop WORDLI (col-start off)) (col-end off))))

	(define (do-one-row off)
		(define pone (+ 1 off))
		(batch-simlist (list-ref row-range off) (col-range pone)))

	(define rpt-one-row
		(make-progress-rpt do-one-row 10 #f
			"Diag: Finished ~D rows in ~D secs (~D/sec)\n"
			60))

	; Perform the similarity calculations, looping over the fat diagonal.
	(for-each (lambda (n) (rpt-one-row n)) (iota depth))
)

; ---------------------------------------------------------------

(define (get-ranked-pairs LLOBJ MI-CUTOFF)
"
  get-ranked-pairs LLOBJ MI-CUTOFF - get a ranked list of word pairs

  This returns a list of word-pairs sorted by rank-MI, from greatest
  to least.  All pairs in the list will have an MI of greater than
  MI-CUTOFF.  An MI-CUTOFF of 4 is recommended, maybe down to 2.
  Setting this too low will provide poor merge suggestions, in addition
  to making it take more time (because setting it low will admit more
  pairs, which take more time to sort.)
"
	; General setup of things we need
	(define sap (do-add-similarity-api LLOBJ))

	; The MI similarity of two words
	(define (mi-sim WA WB)
		(define miv (sap 'pair-count WA WB))
		(if miv (cog-value-ref miv 0) -inf.0))

	; The ranked MI similarity of two words
	(define (ranked-mi-sim WA WB)
		(define miv (sap 'pair-count WA WB))
		(if miv (cog-value-ref miv 1) -inf.0))

	; Get all the similarities. We're going to just hack this, for
	; now, because we SimilarityLinks with both WordNode and WordClassNode
	; in them.
	(define all-sim-pairs (cog-get-atoms 'SimilarityLink))

	; Exclude pairs with a low MI, and also self-similar pairs.
	(define good-sims
		(filter
			(lambda (SIM)
				(define WA (gar SIM))
				(define WB (gdr SIM))
				(and (< MI-CUTOFF (mi-sim WA WB)) (not (equal? WA WB))))
			all-sim-pairs))

	;; Create a word-pair ranking function
	(define (rank-pairs PRLI FUN)
		(sort PRLI
			(lambda (ATOM-A ATOM-B)
				(> (FUN ATOM-A) (FUN ATOM-B)))))

	;; Now sort all of the available pairs according to ranked-MI
	(rank-pairs good-sims (lambda (SIM) (ranked-mi-sim (gar SIM) (gdr SIM))))
)

; ---------------------------------------------------------------

(define (prt-sorted-pairs LLOBJ LST START N)
"
  prt-sorted-pairs START NUM - print list of word pairs and similarities

  Handy-dandy debug utility.
"
	(define sap (do-add-similarity-api LLOBJ))

	; The MI similarity of two words
	(define (mi-sim WA WB)
		(define miv (sap 'pair-count WA WB))
		(if miv (cog-value-ref miv 0) -inf.0))

	; The ranked MI similarity of two words
	(define (ranked-mi-sim WA WB)
		(define miv (sap 'pair-count WA WB))
		(if miv (cog-value-ref miv 1) -inf.0))

	(define len (length LST))
	(define start (min START len))   ; start is just START unless too large.
	(define num (min N (max 0 (- len START))))  ; num is just N unless too large

	(for-each
		(lambda (PR)
			(format #t "ranked-MI = ~6F MI = ~6F (`~A`, `~A`)\n"
				(ranked-mi-sim (gar PR) (gdr PR))
				(mi-sim (gar PR) (gdr PR))
				(cog-name (gar PR))
				(cog-name (gdr PR))))
		(take (drop LST start) num))
)

; ---------------------------------------------------------------

(define (recomp-all-sim LLOBJ WLIST)
"
  recomp-all-sim LLOBJ WLIST - Recompute all existing similarities for
  all words in WLIST. The recomputation is unconditional.

  For each word in WLIST, recompute *all* existing similarities between
  that word and any other word that it already has similarities to. No
  new pairings are created.
"
	(define e (make-elapsed-secs))
	(define sap (do-add-similarity-api LLOBJ))
	(define sms (add-pair-stars sap))
	(define compute-sim (make-simmer LLOBJ))

	(define (recomp-one WX LIGNORE)
		; Loop over all pairs, except the ones we've done already.
		; (as otherwise, each similarity pair gets computed twice)
		(define todo-list (atoms-subtract (sms 'left-duals WX) LIGNORE))
		(compute-sim WX WX) ; Always compute self-similarity.
		(for-each (lambda (WRD)
				(when (not (nil? (sap 'get-pair WRD WX)))
					(compute-sim WRD WX)))
			todo-list))

	; Compute only the triangle of N(N-1)/2 similarities.
	(define (redo-list WX WLI WDONE)
		(recomp-one WX (cons WX WDONE))
		(when (not (nil? WLI))
			(redo-list (car WLI) (cdr WLI) (cons WX WDONE))))

	; all-words are all the words that have similarities.
	(define all-wrds (sms 'left-basis))

	; unaff are all the unaffected words.
	(define unaff (atoms-subtract all-wrds WLIST))

	; aff are the "affected words" - the intersection of provided
	; word list with the words that already have similarities.
	(define aff (atoms-subtract all-wrds unaff))

	(format #t "Will recompute sims for ~3D words (~A unaffected) out of ~3D\n"
		(length aff) (length unaff) (length all-wrds))

	(if (not (nil? aff)) (redo-list (car aff) (cdr aff) '()))

	(format #t "Recomputed sims for ~3D words out of ~3D in ~A secs\n"
		(length aff) (length all-wrds) (e))
)

; ---------------------------------------------------------------

(define-public (setup-initial-similarities LLOBJ NRANK)
"
  setup-initial-similarities LLOBJ NRANK -- Compute a block matrix
  of similarities for the top-ranked words.

  All of the words appearing in the left-basis of LLOBJ are ranked
  by the total observation count on them. Then the top NRANK of them
  are taken, and the similarities between them are computed.

  If similarity values have already been recorded for any given
  word-pair, they will NOT bet recomputed.
"
	(define e (make-elapsed-secs))

	; Start by getting the ranked words.  Note that this may include
	; WordClass nodes as well as words.
	(define ranked-words (rank-words LLOBJ))
	(format #t "Done ranking words in ~A secs\n" (e))

	; Load similarity-pairs; pointless to recompute if we have them!
	((do-add-similarity-api LLOBJ) 'fetch-pairs)

	; Create similarities for the initial set.
	(compute-diag-mi-sims LLOBJ ranked-words 0 NRANK)
	(format #t "Done computing MI similarity in ~A secs\n" (e))
)

; ---------------------------------------------------------------

(define (compute-class-sim LLOBJ WCLASS)
"
  compute-class-sim LLOBJ WCLASS - Compute the similarity between
  WCLASS and all other existing classes. The computation is
  unconditional.
"
	(define compute-sim (make-simmer LLOBJ))

	(for-each (lambda (WC) (compute-sim WCLASS WC))
		(LLOBJ 'get-clusters))
)

; ---------------------------------------------------------------
