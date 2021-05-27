{:user
 {:dependencies [[pjstadig/humane-test-output "0.8.3"]
                 [refactor-nrepl "2.5.1"]
                 [cider/cider-nrepl "0.26.0-SNAPSHOT"]]
  :injections [(require 'pjstadig.humane-test-output)
               (pjstadig.humane-test-output/activate!)]
  :plugins [[lein-ancient "1.0.0-RC3"]
            [lein-pprint "1.2.0"]
            [com.jakemccrary/lein-test-refresh "0.21.1"]
            [cider/cider-nrepl "0.26.0-SNAPSHOT"]]}}
