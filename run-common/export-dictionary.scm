#! /usr/bin/env -S guile
!#
;
; export-dictionary.scm
;
; After grammatical classification has been completed, a Link Grammar
; dictionary containing the results can be exported. This script
; performs that export.
;
(load "cogserver.scm")

; Load up the grammatical classes.
(display "Fetch all grammatical classes\n")
(define gca (make-gram-class-api))
(gca 'fetch-pairs)

; Close the DB to avoid accidental corrruption!?
(barrier storage-node)
(cog-close storage-node)

; Create singleton classes. XXX This should be done elsewhere!?
(display "Create singleton classes\n")
(define pca (make-pseudo-cset-api))
(define psa (add-pair-stars pca))
(define asc (add-singleton-classes psa))
(asc 'create-hi-count-singles 1)

; Compute MI. This is needed for LG costs.
; XXX this and above steps should move to `marginals-dict.scm` !?
(display "Computing Link Grammar costs\n")
(define gcs (add-pair-stars gca))
(define gcf (add-wordclass-filter gcs))
(batch-all-pair-mi gcf)

; (print-matrix-summary-report gcf)

; Perform the actual export
; XXX get dictionary name from config file!?
(display "Exporting Dictionary\n")
(use-modules (opencog nlp lg-export))
(export-csets gcf "dict.db" "EN_us")
