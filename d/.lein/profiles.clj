{:user
 {:plugins [
            [cider/cider-nrepl "0.7.0-SNAPSHOT"]
            [cljs-template "0.1.5"]
            [com.palletops/pallet-lein "0.8.0-alpha.1"]
            [lein-clojars "0.9.0"]
            [lein-difftest "2.0.0"]
            [lein-localrepo "0.4.0"]
            [lein-marginalia "0.7.0"]
            [lein-pprint "1.1.1"]
            [lein-swank "1.4.5"]
            [lein-tar "1.0.2"]
            ]
  :dependencies [[pjstadig/humane-test-output "0.6.0"]]
  :injections [(require 'pjstadig.humane-test-output)
               (pjstadig.humane-test-output/activate!)]}}
