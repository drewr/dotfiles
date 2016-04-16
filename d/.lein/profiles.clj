{:user
 {:plugins [
            [cider/cider-nrepl "0.12.0-SNAPSHOT"]
            [com.palletops/pallet-lein "0.8.0-alpha.1"]
            [lein-ancient "0.6.10"]
            [lein-localrepo "0.5.3"]
            [lein-marginalia "0.8.0"]
            [lein-pprint "1.1.2"]
            [lein-tar "3.3.0"]
            [lein-typed "0.3.5"]
            ]
  :dependencies [[pjstadig/humane-test-output "0.8.0"]
                 [org.clojure/tools.nrepl "0.2.12"]]
  :injections [(require 'pjstadig.humane-test-output)
               (pjstadig.humane-test-output/activate!)]}}
