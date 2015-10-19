(require 'boot.repl)
(swap! boot.repl/*default-dependencies*
       concat '[[cider/cider-nrepl "0.10.0-20150910.083528-24"]
                [pjstadig/humane-test-output "0.7.0"]])

(swap! boot.repl/*default-middleware*
       conj 'cider.nrepl/cider-middleware)
