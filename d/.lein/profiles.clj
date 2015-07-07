{:user
 {:plugins [
            [cider/cider-nrepl "0.9.1"]
            [com.palletops/pallet-lein "0.8.0-alpha.1"]
            [lein-localrepo "0.5.3"]
            [lein-marginalia "0.8.0"]
            [lein-pprint "1.1.2"]
            [lein-tar "3.3.0"]
            [lein-typed "0.3.5"]
            ]
  :dependencies [[pjstadig/humane-test-output "0.6.0"]]
  :injections [(require 'pjstadig.humane-test-output)
               (pjstadig.humane-test-output/activate!)]}}
