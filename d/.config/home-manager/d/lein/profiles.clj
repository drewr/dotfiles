{:user
 {:dependencies [[pjstadig/humane-test-output "0.8.3"]
                 [refactor-nrepl "2.5.1"]
                 [cider/cider-nrepl "0.53.2"]]
  :injections [(require 'pjstadig.humane-test-output)
               (pjstadig.humane-test-output/activate!)]
  :plugins [[lein-ancient/lein-ancient "1.0.0-RC3"]
            [lein-pprint/lein-pprint "1.2.0"]
            [lein-count/lein-count "1.0.9"]
            [com.jakemccrary/lein-test-refresh "0.21.1"]
            [cider/cider-nrepl "0.53.2"]]}}
