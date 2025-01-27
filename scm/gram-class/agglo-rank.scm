;
; agglo-rank.scm
;
; Loop over all words, merging them into grammatical categories.
; Agglomerative clustering.
;
; Copyright (c) 2021 Linas Vepstas
;
; ---------------------------------------------------------------------
; OVERVIEW
; --------
; This file manages the top-most loop for traversing over all words,
; and assigning them to grammatical clusters. This file does not
; provide tools for judging similarity, nor does it provide the
; low-level merge code.  It only manages the top loop.
;
; This is basically the general concept of "agglomerative clustering",
; which is what is (in effect) implemented in this file.
;
; There are other styles of doing agglomerative clustering, implemented
; in `attic/agglo-loops.scm` and `attic/agglo-pairwise.scm`. They work,
; but are more complicated and don't work as well.  (I think they don't
; work as well, but this has not been double-checked experimentally.)
;
; Agglomerative clustering
; ------------------------
; This file implements a form of ranked clustering. It assumes that
; there is a pair-ranking function that will report the next pair to
; be merged together. That pair may be a  pair of words, a word and
; an existing cluster, or a pair of clusters.
;
; This is basic, the `cliques/democratic voting` thing is next, but its
; more complicated, so we do this first.
;
; Assumptions:
; * This assumes that shapes are being used. This is a fundamental
;   requirement for performing connector merges, so we are not going
;   to try to pretend to support anything else.
; * This assumes that support marginals have been computed, and have
;   been loaded into RAM. it will keep support marginals updated, as
;   words are merged.
;
; Notes:
; * make sure WordClassNodes and the MemberLinks are loaded
; ---------------------------------------------------------------------

(use-modules (srfi srfi-1))
(use-modules (ice-9 optargs)) ; for define*-public
(use-modules (opencog) (opencog matrix) (opencog persist))

; Compile-time constant -- should we trrack entropies, or not?
; Setting this to #t requires that not only must the baseline
; entropies be recomputed, but also that the frequencies for pairs
; be stored, including the frequencies for CrossSections. This
; puts a big burden on storage, as normally, CrossSections are
; not stored. A different alternative would be to use entropies
; computed on-the-fly from counts on CrossSections, as these are
; always correct. But this adds yet more CPU overhead just to log
; some stats that are not  that terribly interesting. See the
; Diary Part Five for actual values.
(define TRACK-ENTROPY #f)

; ---------------------------------------------------------------

(define (main-loop LLOBJ MERGE-FUN NRANK LOOP-CNT)
"
  Unleash the fury. Inside of a loop, apply the MERGE-FUN to the
  top-ranked word-pair, for LOOP-CNT iterations. After each
  iteration, the similarities for a few more words are computed,
  so that, no matter the LOOP-CNT, there is a suitably deep set of
  word-pair similarities to rank and consider.
"
	; Get rid of all MI-similarity scores below this cutoff.
	(define MI-CUTOFF 4.0)

	; Logging of the number of merges perfomed so far.
	(define log-anchor (LLOBJ 'wild-wild))
	(define count-location (Predicate "merge-count"))
	(define count-log (cog-value log-anchor count-location))
	(define base-done-count (inexact->exact
		(if (nil? count-log) 0 (cog-value-ref count-log 0))))
	(define (current-count N) (+ 1 N base-done-count))
	(define (update-done-count N)
		(cog-set-value! log-anchor count-location (FloatValue N)))

	; Offset on number of similarities to compute
	(define NSIM-OFFSET base-done-count)

	; How many more similarities to compute each step.
	(define GRO-SIZE 2)

	; Range of similarities to compute.
	(define (diag-start N) (+ N NSIM-OFFSET))
	(define (diag-end N) (+ NRANK (* GRO-SIZE (+ N NSIM-OFFSET))))

	(define log-dataset-stuff (make-merge-logger LLOBJ))

	(for-each
		(lambda (N)
			(define e (make-elapsed-secs))
			(define sorted-pairs (get-ranked-pairs LLOBJ MI-CUTOFF))
			(format #t "------ Round ~A Next in line:\n" (current-count N))
			(prt-sorted-pairs LLOBJ sorted-pairs 0 12)

			(define top-pair (car sorted-pairs))

			; Log some maybe-useful data...
			(log-dataset-stuff top-pair)

			; Do the actual merge
			(MERGE-FUN (current-count N) (gar top-pair) (gdr top-pair))
			(update-done-count (current-count N))

			(format #t "------ Completed merge in ~A secs\n" (e))

			; Expand the size of the universe
			(define ranked-words (rank-words LLOBJ))

			; (compute-diag-mi-sims LLOBJ ranked-words (diag-start N) (diag-end N))
			(compute-diag-mi-sims LLOBJ ranked-words 0 (diag-end N))
			(format #t "------ Extended the universe in ~A secs\n" (e))
		)
		(iota LOOP-CNT))
)

; ---------------------------------------------------------------

(define (get-affected-basis LLOBJ WRD-LIST)
"
  get-affected-basis LLOBJ WRD-LIST - Return two lists of basis
  elements affected by the merge.

  The first list is the left basis, the second list is the right-basis.
"
	; Gather together all of the DJ's for all the words in the list.
	; These will, in general, be heavily duplicated.
	(define dj-set (make-atom-set))

	; Gather together all affected words.
	(define wrd-set (make-atom-set))
	(for-each wrd-set WRD-LIST)

	; Add pair to the margin-sets.
	(define (pair-margins PAIR)
		(wrd-set (LLOBJ 'left-element PAIR))
		(dj-set (LLOBJ 'right-element PAIR)))

	(define (cross-margins PAIR)
		(for-each pair-margins (LLOBJ 'make-cross-sections PAIR)))

	; Add pair to the margin-sets, and also the matching sections
	; and cross-sections.
	(define (expand-margins PAIR)
		(dj-set (LLOBJ 'right-element PAIR))
		(if (equal? 'Section (cog-type PAIR))
			(cross-margins PAIR)

			; So 'get-section should have worked, except sometimes
			; on restart after a crash, the section might be absent.
			; So that's weird. Fixed a variant of this bug just a
			; few commits earlier.
			(let ((sect (LLOBJ 'make-section PAIR)))
				(pair-margins sect)
				(cross-margins sect))))

	; Populate the margin sets.
	(for-each
		(lambda (WRD) (for-each expand-margins (LLOBJ 'right-stars WRD)))
		WRD-LIST)

	; Margins are battered by individual pair changes, too.
	(define affected-djs (dj-set #f))
	(for-each (lambda (DJ) (for-each wrd-set (LLOBJ 'left-duals DJ)))
		affected-djs)

	(list (wrd-set #f) affected-djs)
)

(define (recompute-entropies LLOBJ wrd-list dj-list)
"
  recompute-entropies LLOBJ wrd-list dj-list -- Recompute marginal entropy

  The marginal entropies and the marginal MI for MI(w,d) appears to be
  interesting. So keep these up to date.

  At this time, these are all just 'interesting'; they are not actually
  needed for anything, so this computation could be skipped. All that
  would happen is that the logging of data would fail.

  This does take a significant amount of CPU time!
"
	(define freq-obj (make-compute-freq LLOBJ))
	(define ent-obj (add-entropy-compute LLOBJ))
	(define sup-obj (add-support-api LLOBJ))

	(freq-obj 'init-freq)

	(define e (make-elapsed-secs))

	; Entropies need the frequencies recomputed on the pairs
	(for-each
		(lambda (WRD)
			(for-each (lambda (PR) (freq-obj 'cache-pair-freq PR))
				(LLOBJ 'right-stars WRD)))
		wrd-list)

	; The freq-obj 'cache-left-freq is a trivial divide of the marginal
	; count by the total count, and nothing more. The 'cache-left-entropy
	; just takes some logs, and nothing more.
	;
	; XXX Is this really needed? Detailed balance means that neither
	; the marginal counts on the DJ's, nor the marginal frrequency or
	; entropy should change. Validating that nothing changed could be
	; a reasonable data-integrity check.
	(for-each
		(lambda (DJ)
			(when (< 0 (sup-obj 'left-count DJ))
				(freq-obj 'cache-left-freq DJ)
				(store-atom (ent-obj 'cache-left-entropy DJ))))
		dj-list)

	; Unlike the above, this is needed, as clustering redistributes
	; the counts and thus alters marginals.
	(for-each
		(lambda (WRD)
			(when (< 0 (sup-obj 'right-count WRD))
				(freq-obj 'cache-right-freq WRD)
				(store-atom (ent-obj 'cache-right-entropy WRD))))
		wrd-list)

	(format #t "------ Recomputed entropies in ~A secs\n" (e))
)

(define (recompute-mmt LLOBJ wrd-list dj-list)
"
  recompute-mmt LLOBJ wrd-list dj-list -- Recompute MMT for for the
  basis elements in wrd-list dj-list.

  This recomputes the marginals for support and counts for the words
  in the WRD-LIST, and also for the disjuncts attached to those words.
  In particular, this recomputes the N(*,d) which is needed by MM^T.
"
	(define sup (add-support-api LLOBJ))
	(define psu (add-support-compute LLOBJ))
	(define atc (add-transpose-compute LLOBJ))

	(define dj-orphan (make-atom-set))
	(define wrd-orphan (make-atom-set))

	; This for-each loop accounts for 98% of the CPU time in typical cases.
	; We recompute the marginals for this DJ. If the marginal is zero,
	; then we can delete the DJ and everything it's a part of. But we
	; defer deletion until later, after the word marginals are computed.
	(for-each
		(lambda (DJ)
			(define marg (psu 'set-left-marginals DJ))
			(if (< 0 (sup 'left-count DJ))
				(store-atom marg) (dj-orphan marg)))
		dj-list)

	; Same as above, but for the rows.
	(for-each
		(lambda (WRD)
			(define marg (psu 'set-right-marginals WRD))
			(if (< 0 (sup 'right-count WRD))
				(store-atom marg) (wrd-orphan marg)))
		wrd-list)

	(for-each
		(lambda (WRD) (store-atom (atc 'set-mmt-marginals WRD)))
		wrd-list)

	; (Optional) Recompute entropies.
	; Optional, cause it's not strictly needed (at this time)
	; but it does seem to offer some interesting data.
	; This incurs additional compute cost, though.
	(if TRACK-ENTROPY
		(recompute-entropies LLOBJ wrd-list dj-list))

	(list (wrd-orphan #f) (dj-orphan #f))
)

(define (delete-orphans LLOBJ left-marg right-marg)
"
  delete-orphans left-marg right-marg -- delete marginals.
"
	; In the current design, LLOBJ will always be a covering object.
	; The base is what is covered with shapes.
	(define base-obj
		(if (LLOBJ 'provides 'cover-base)
			(LLOBJ 'cover-base) #f))

	; Get rid of word-marginals
	(for-each (lambda (WMARG)
		(when (cog-atom? WMARG)
			(let ((WRD (LLOBJ 'left-element WMARG)))
				(cog-delete! WMARG)
				(cog-delete-recursive! WRD))))
		left-marg)

	; Get rid of disjunct marginals. These are one of two types:
	; either they are ShapeLinks, created by the covering object,
	; or they are something else, from the base object. For example,
	; the gram-class-api uses a ListLink, of which the 'right-elt
	; is a ConnectorSeq.  We want to delete that ConnectorSeq.
	;
	(for-each (lambda (DJMARG)
			(when (cog-atom? DJMARG)
				(if (eq? 'ShapeLink (cog-type DJMARG))
					(cog-delete! DJMARG)
					(let ((DJ (base-obj 'right-element DJMARG)))
						(cog-delete! DJMARG)
						(cog-delete-recursive! DJ)))))
		right-marg)
)

(define (recompute-mmt-final LLOBJ)
"
  recompute-mmt-final LLOBJ -- recompute grand totals for the MM^T case
"
	(define asc (add-support-compute LLOBJ))
	(define atc (add-transpose-compute LLOBJ))

	; Computing the 'set-left-totals takes about 97% of the total
	; time in this function, and about 8% of the grand-total time
	; (of merging words). Yet I suspect that it is not needed...
	; If the totals are not recomputed, then the matrix-summary-report
	; is borken.
	(store-atom (asc 'set-left-totals))   ;; is this needed? Its slow.
	(store-atom (asc 'set-right-totals))  ;; is this needed?
	(store-atom (atc 'set-mmt-totals))

	; (Optional) Recompute the grand-total entropy
	; Do this if the entropy marginals are being done.
	(when TRACK-ENTROPY
		(let ((ent-obj (add-entropy-compute LLOBJ)))
			(store-atom (ent-obj 'cache-entropy))))
)

(define (recompute-marginals LLOBJ WRD-LIST)
"
  recompute-marginals LLOBJ WRD-LIST - Recompute marginals after merge.

  Recomputes all marginals for all Sections and CrossSections touched
  by WRD-LIST. Deletes those which have zero counts left. Also
  recomputes the MMT values, needed by the similarity calculations.
"
	(define e (make-elapsed-secs))
	; Clobber first; else the ; duals and stars are wrong, which ruins
	; the support calculations.
	(LLOBJ 'clobber)

	; Get all of the words and dj's touched by WRD-LIST
	(define affected-basis (get-affected-basis LLOBJ WRD-LIST))
	(define wrd-list (first affected-basis))
	(define dj-list (second affected-basis))
	(format #t "------ Find affected basis of (~A, ~A) in ~A secs\n"
		(length wrd-list) (length dj-list) (e))

	; Redo marginals before deleting empty sections, as otherwise
	; the empties fail to show up in the basis.
	(define orphans (recompute-mmt LLOBJ wrd-list dj-list))

	; Now clobber all the empty sections and cross-sections.
	(remove-all-empty-sections LLOBJ WRD-LIST)

	; The orphans are the orphaned marginals, i.e. the marginals
	; with zero counts. Get rid of them too.
	(define left-marg (first orphans))
	(define right-marg (second orphans))
	(delete-orphans LLOBJ left-marg right-marg)

	; Recompute the grand-totals. Do this only after deleting the
	; zero-count entries, as otherwise these get messed up.
	(LLOBJ 'clobber)
	(recompute-mmt-final LLOBJ)

	; Return the list of all words that were touched.
	wrd-list
)

; ---------------------------------------------------------------

(define*-public (in-group-cluster LLOBJ
	QUORUM COMMONALITY NOISE NRANK LOOP-CNT
	#:optional (PRECISE-SIM #f))
"
  in-group-cluster LLOBJ QUORUM NRANK LOOP-CNT PRECISE-SIM - clustering.

  Loops over a list of the most similar words, and unifies them into a
  cluster. Multiple words are selected at the same time to create a
  cluster.  The selection of words is done by selecting an 'in-group'
  of words that are all similar to one-another. The selection of
  ConnectorSeq's to be merged is done by majority voting to determine
  those ConnectorSeq's that the majority of the in-group have in common.
  The size of the in-group is adjusted to maximize commonality.

  There are three important parameters that determine the operation, and
  two more that control the overall loop.

  The QUORUM parameter is a floating point number, between 0.0 and 1.0
  that determines how many of the in-group members must share a
  ConnectorSeq for it to be considered to be held 'in common'.  (Think
  of a group of individuals having some trait in common.)

  Recommended values for QUORUM are in the 0.4 to 0.9 range. At the
  moment, 0.7 seems to work best.

  The algo begins by selecting the two words that are deemed to be the
  most similar to one-another, as reported by the `add-similarity` API.
  These two are the initial members of an 'in-group'. Other similar
  words are added as members, to create the largest possible in-group
  that is still exclusionary. The members of the in-group must have
  large pair-wise similarity.  It must also be exclusive, in that if the
  similarity threshold was reduced, membership would become explosively
  large.  (From experiments, it can be seen that as the similarity
  threshold is lowered, the group stays small, growing slowly, or not
  at all. Then there is an inflection point, where the group suddenly
  grows explosively large, gaining many members despite a small change
  in the similarity threshold. The in-group is selected to be the
  largest group below that inflection.)

  After the formation of the in-group, a poll is taken to see how many
  ConnectorSeq's the group has in common (as controlled by QUORUM,
  described above.) The 'commonality' is this fraction. If the
  commonality is less than the COMMONALITY parameter, then the size of
  the in-group is reduced, by removing the least-similar member, and
  a poll is taken again. This continues until either the commonality is
  greater than the COMMONALITY parameter, or until the commonality
  drops, as compared to the previous group. (The commonality can drop,
  because in a smaller group, it can be harder to have a quorum.)

  Recommended values for COMMONALITY are in the 0.05 to 0.25 range.
  At the moment 0.2 seems to work well. In general, the 'commonality'
  is usually very low, and so this fraction is almost enever exceeded.
  In other words, this parameter has almost no effect on results.

  NOISE is a noise-floor threshold. If a given section has a count equal
  or less than the NOISE parameter, it gets no vote in determining the
  commonality.  (Think of a group of individuals, one of whom has a
  minor quirky trait. One does not wish to have that minor trait to
  interfer with the group as a whole, thus it is ignored.)

  The NOISE parameter also plays a second role (perhaps it should be
  split out into a distinct parameter?) All sections with a count equal
  or below the noise floor are unconditionally merged into the cluster.

  Recommended value for NOISE is 0 to 4.  Note that, due to Zipfian
  distributions, almost all sections have extremely low counts. Thus,
  the (vast) majority of merged sections will be those below this noise
  floor. In other words, results are sharply dependent on this parameter.

  All ConnectorSeq's that have been determined to be held in common by
  the in-group are then merged into the cluster. Note that the process
  of voting has both a narrowing and a broadening effect. Narrowing, in
  that once a group of similar words have been selected, not all
  ConSeq's are added to the cluster. The goal of this narrowing is to
  explcitly factor out distinct word-senses. Thus, a word like 'saw',
  which can be both noun and verb, will have it's noun-like ConSeq's
  merged with other nouns, while the verb-like ConSeq's are left behind,
  to be merged with other verbs.

  This algo also has a broadening effect: By majority vote, once a
  ConSeq is accepted into the cluster, all of those words will now share
  that ConSeq, even if some of them had not previously. The goal of this
  broadening is to generalize from particulars to generalities.

  There are three control parameters, NRANK, LOOP-COUNT and PRECISE-SIM.

  LOOP-COUNT is the number of times to run the loop, performing a
  select-and-merge step each time around.

  NRANK is the number of words to rank, before similarity computations
  are performed. The words are ranked according to the grand-total
  observation count on them, most frequent words first. Then the
  pair-wise similarities are computed for the top NRANK words (thus,
  a total of NRANK * (NRANK - 1) / 2 similarities are computed.) The
  goal here is to avoid having to compute simiarities between all words,
  which is computationaly infeasible. Experimentally, it is unlikely
  that frequent words are similar to infrequent ones, except in
  pathological cases. The word-pair with the highest similarity is then
  used to seed the in-group at the start of each loop.

  As the loop runs, additional similarities are computed each step. The
  number of words with similarity scores on them is kept at NRANK plus
  twice the number of loops that have been run. This provides for a
  deeper buffer, the rarer the words get. That is, there are many
  less-common words that are similar to one-another, and these have
  widly-varying rank; the size of the band of similarities must increase
  to capture these.

  Recommended value for NRANK is between 100 and 200.

  PRECISE-SIM is an optional parameter; it defaults to #f. If set to #t,
  then all similarities between all words affected by the merge, even if
  they are affected indirectly, are recomputed. If set to #f, then the
  only similarities recomputed are those for the words that were merged.
  This recomputation can take up most of the CPU time, and so it defaults
  to #f.  It is not yet clear how much this affects results. Probably not
  much, or not at all.

  Status: This code is complete, fully-debugged, stable, well-tested.
"
	(setup-initial-similarities LLOBJ NRANK)

	; Log what we actually used.
	(define *-log-anchor-* (LLOBJ 'wild-wild))
	(cog-set-value! *-log-anchor-* (Predicate "quorum-comm-noise")
		(FloatValue QUORUM COMMONALITY NOISE NRANK))

	; Record the classes as they are created.
	(define log-class (make-class-logger LLOBJ))

	; Create the function that determines group membership.
	(define jaccard-select (make-jaccard-selector LLOBJ
		QUORUM COMMONALITY NOISE))

	; Create the function that performs the merge.
	(define merge-majority (make-merge-majority LLOBJ QUORUM NOISE #t))

	; ------------------------------
	; Main workhorse function
	(define (perform-merge N WA WB)
		(define e (make-elapsed-secs))
		(format #t "------ Start merge ~D with seed pair `~A` and `~A`\n"
			N (cog-name WA) (cog-name WB))

		(define ranked-words (rank-words LLOBJ))
		; Approximation to number of words with sims.
		; This is overkill; NRANK is more than enough!
		(define n-to-take (inexact->exact
			(min (length ranked-words) (+ NRANK (* 3 N)))))
		(define words-with-sims (take ranked-words n-to-take))

		(define in-grp (jaccard-select WA WB words-with-sims))
		(format #t "In-group size=~A:" (length in-grp))
		(for-each (lambda (WRD) (format #t " `~A`" (cog-name WRD))) in-grp)
		(format #t "\n")

		(define wclass (make-class-node LLOBJ in-grp))
		(merge-majority wclass in-grp)

		(format #t "------ Merged into `~A` in ~A secs\n"
			(cog-name wclass) (e))

		; Recompute marginals after merge.
		(define touched-words (recompute-marginals LLOBJ (cons wclass in-grp)))
		(format #t "------ Recomputed MMT marginals in ~A secs\n" (e))

		; After merging, recompute similarities for the words
		; that were touched. We have two choices here: recompute
		; sims only for the words that were directly merged, as these
		; are clearly directly affected. Or we recompute the entire
		; universe of words that were just peripherally affected.
		; Recomputing the univese causes the whole algo to run about
		; 10x slower. In exchange, we maybe get better results? Or maybe
		; not? Unclear, unknown at this time, might no matter.
		(if PRECISE-SIM
			(recomp-all-sim LLOBJ touched-words)
			(recomp-all-sim LLOBJ (filter cog-atom? in-grp)))

		; Always compute self-similarity of the new word-class.
		; Optional; this is logged by the logger.
		((make-simmer LLOBJ) wclass wclass)

		; Optional; compute similarity between this and all other
		; classes. This is used to compute and log the orthogonality
		; of the classes. It provides an intersting statistic.
		(compute-class-sim LLOBJ wclass)

		(log-class wclass) ; record this in the log

		(format #t "------ Recomputed MI in ~A secs\n" (e))
	)

	; --------------------------------------------
	; Unleash the fury
	(main-loop LLOBJ perform-merge NRANK LOOP-CNT)
)

; ---------------------------------------------------------------
#! ========
;
; Example usage

(define pca (make-pseudo-cset-api))
(define pcs (add-pair-stars pca))
(define sha (add-covering-sections pcs))
(sha 'fetch-pairs)
(sha 'explode-sections)

; If this hasn't been done, then it needs to be!
(define bat (batch-transpose sha))
(bat 'mmt-marginals)

(define sap (add-similarity-api sha #f "shape-mi"))
(define asm (add-symmetric-mi-compute sha))

==== !#
