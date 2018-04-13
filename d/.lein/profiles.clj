{:user
 {:dependencies [[pjstadig/humane-test-output "0.8.3"]]
  :injections [(require 'pjstadig.humane-test-output)
               (pjstadig.humane-test-output/activate!)]
  :plugins [[com.palletops/pallet-lein "0.8.0-alpha.1"]
            [lein-ancient "0.6.10"]
            [lein-pprint "1.1.2"]
            [com.jakemccrary/lein-test-refresh "0.21.1"]]}}

