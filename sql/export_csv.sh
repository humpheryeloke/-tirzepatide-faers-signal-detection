#!/bin/sh
# Exports the out_* views to ./outputs as quoted CSV. Run from the repo root:  sh sql/export_csv.sh
mkdir -p outputs
for v in event_overview hidden_signals subgroup_results stratum_sizes cleaning_log kpi; do
  mysql faers_pv --batch --raw -e "SELECT * FROM out_$v" \
    | sed -e 's/"/""/g' -e 's/\t/","/g' -e 's/^/"/' -e 's/$/"/' -e 's/"NULL"//g' > outputs/$v.csv
  echo "$v: $(($(wc -l < outputs/$v.csv)-1)) rows"
done
