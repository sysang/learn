;
; cogserver-gram.scm
;
; Run everything needed for the language-learning grammatical class
; clustering pipeline. Starts the CogServer, opens the database, loads
; the disjuncts in the database (which can take an hour or more!).
;
(load "cogserver.scm")

; Load up the disjuncts -- this can take over half an hour!
; XXX Do we need to actually do this? I think not!?
(display "Fetch all disjuncts. This may take well over half-an-hour!\n")

; The object which will be providing disjunct-counts for us.
(define cset-obj (make-pseudo-cset-api))
(define star-obj (add-pair-stars cset-obj))
(cset-obj 'fetch-pairs)

; Check to see if the marginals have been computed.
; Common error is to forget to do them manually.
; So we check, and compute if necessary.
(catch #t
	(lambda () ((add-report-api star-obj) 'num-pairs))
	(lambda (key . args)
		; User needs to run `compute-mst-marginals.sh`
		(format #t "Disjunct marginals missing; go back and compute them!\n")
		#f))

(print-matrix-summary-report star-obj)

; (cog-close storage-node)
