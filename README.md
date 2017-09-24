presage-predictor.el defines dynamic completion backend for company-mode 
that are based on presage predictor.

Presage predictor for emacs:
- is configurable through programmable presage predictor

When the first completion is requested in company mode,
 presage-predictor.el starts a separate presage
process.  presage-predictor.el then uses this process to do the actual
completion and includes it into Emacs completion suggestions.

## INSTALLATION

1. copy presage-predictor.el into a directory that's on Emacs load-path
2. add this into your .emacs file:

        (autoload 'company-presage-backend
          "presage-predictor"
          "PRESAGE PREDICTOR completion backend")
        (add-to-list 'company-backends 'company-presage-backend)
        
  or simpler, but forces you to load this file at startup:

        (require 'presage-predictor)
        (presage-predictor-setup)

3. reload your .emacs (M-x `eval-buffer') or restart

Once this is done, type as usual to do dynamic completion from
company mode. Note that the first completion is slow, as emacs
launches a new presage process.

You'll get better results if you use  language models based on a "good" training corpus of text.
text2ngram tool generates n-gram language models from a given training text corpora.
 https://sourceforge.net/p/presage/presage/ci/master/tree/FAQ

Right after your language model trained, and whenever you
make changes to /etc/presage.xml, call `presage-predictor-reset' to make
sure presage predictor takes your new settings into account.

## CAVEATS

Using a separate process for doing the completion has several
important disadvantages:

- presage predictor is slower than standard emacs completion
- the first completion can take a long time, since a new presage process
  needs to be started and initialized


## COMPATIBILITY

presage-predictor.el is known to work on Emacs 22 through 24.4 under
Linux.
