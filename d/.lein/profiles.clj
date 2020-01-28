{:user
 {:dependencies [[pjstadig/humane-test-output "0.8.3"]
                 [refactor-nrepl "2.4.0"]
                 [cider/cider-nrepl "0.18.0-SNAPSHOT"]]
  :injections [(require 'pjstadig.humane-test-output)
               (pjstadig.humane-test-output/activate!)]
  :plugins [[com.palletops/pallet-lein "0.8.0-alpha.1"]
            [lein-ancient "0.6.10"]
            [lein-pprint "1.2.0"]
            [com.jakemccrary/lein-test-refresh "0.21.1"]
            [cider/cider-nrepl "0.19.0"]]}}

