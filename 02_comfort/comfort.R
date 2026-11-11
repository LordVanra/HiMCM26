# comf::calcSET documentation reviewed 2026-11-11:
# https://search.r-project.org/CRAN/refmans/comf/html/calcSET.html
# Every formal argument is supplied. Installation and source audit remain required.
set_value <- function(condition,group,config) {
  if(!requireNamespace('comf',quietly=TRUE)) stop('comf is not installed')
  if(as.character(utils::packageVersion('comf'))!=config$comf_version) stop('Installed comf version not audited')
  args<-list(ta=condition$temperature_C,tr=condition$radiant_temperature_C,
    vel=condition$local_airspeed_m_s,rh=condition$RH_percent,
    clo=group$clo,met=group$met,wme=group$wme,sa=group$sa,
    pb=condition$pressure_Pa*760/101325, # exact standard atmosphere/torr definition
    ltime=group$ltime,ht=group$ht,wt=group$wt,tu=group$tu,obj='set',
    csw=group$csw,cdil=group$cdil,cstr=group$cstr,bodyPosition=group$bodyPosition)
  if(!setequal(names(formals(comf::calcSET)),names(args))) stop('Unreviewed calcSET signature')
  if(any(vapply(args,anyNA,logical(1)))) stop('Missing explicit SET argument')
  value<-do.call(comf::calcSET,args)
  if(length(value)!=1 || !is.numeric(value) || !is.finite(value)) stop('Invalid SET result')
  as.numeric(value)
}

run_comfort <- function(config,inputs=load_inputs(config),physics=NULL) {
  validate_inputs(config,inputs)
  if(is.null(physics)) physics<-run_physics(config,inputs)
  z<-physics$zone_conditions
  keys<-c('case_id','timestamp','zone_id')
  d<-merge(z,physics$groups[c(keys,'group_id','people')],by=keys,all=TRUE)
  if(anyNA(d[c('temperature_C','group_id','people')])) stop('Unmatched exposure or group')
  d$SET_C<-vapply(seq_len(nrow(d)),function(i) {
    g<-inputs$comfort_groups[inputs$comfort_groups$group_id==d$group_id[i],,drop=FALSE]
    if(nrow(g)!=1) stop('Group must resolve exactly once')
    set_value(d[i,],g,config)
  },numeric(1))
  d$hot_discomfort<-pmax(0,d$SET_C-config$comfort_upper_C)
  d$comfortable<-d$SET_C>=config$comfort_lower_C & d$SET_C<=config$comfort_upper_C
  d$person_hours<-d$people*d$dt_hours
  d$baseline_SET_C<-NA_real_
  for(i in seq_len(nrow(d))) {
    sc<-inputs$scenarios[inputs$scenarios$case_id==d$case_id[i],]
    b<-d[d$case_id==sc$baseline_case_id & d$zone_id==d$zone_id[i] & d$timestamp==d$timestamp[i] & d$group_id==d$group_id[i],,drop=FALSE]
    if(nrow(b)!=1) stop('Baseline pairing must be one-to-one within same partition')
    if(b$people!=d$people[i] || b$dt_hours!=d$dt_hours[i] || b$pressure_Pa!=d$pressure_Pa[i]) stop('Baseline changes population/time/pressure')
    wc<-inputs$weather[inputs$weather$case_id==d$case_id[i] & inputs$weather$timestamp==d$timestamp[i],]
    wb<-inputs$weather[inputs$weather$case_id==sc$baseline_case_id & inputs$weather$timestamp==d$timestamp[i],]
    if(!identical(wc[c('temperature_C','RH_percent','pressure_Pa')],wb[c('temperature_C','RH_percent','pressure_Pa')])) {
      if(!isTRUE(all.equal(unname(as.matrix(wc[c('temperature_C','RH_percent','pressure_Pa')])),unname(as.matrix(wb[c('temperature_C','RH_percent','pressure_Pa')]))))) stop('Weather differs from baseline')
    }
    d$baseline_SET_C[i]<-b$SET_C
  }
  d$benefit_person_degC_h<-d$person_hours*(pmax(0,d$baseline_SET_C-config$comfort_upper_C)-d$hot_discomfort)
  d$residual_person_degC_h<-d$person_hours*d$hot_discomfort
  d$comfortable_person_h<-d$person_hours*d$comfortable
  d$incremental_comfortable_person_h<-d$person_hours*(d$comfortable-(d$baseline_SET_C>=config$comfort_lower_C & d$baseline_SET_C<=config$comfort_upper_C))
  totals<-lapply(split(d,d$case_id),function(a) {
    sc<-inputs$scenarios[inputs$scenarios$case_id==a$case_id[1],]
    rr<-physics$resources[physics$resources$case_id==a$case_id[1],]
    E<-sum(rr$power_kW*rr$dt_hours); B<-sum(a$benefit_person_degC_h); ph<-sum(a$person_hours)
    data.frame(case_id=a$case_id[1],venue_id=sc$venue_id,scenario_id=sc$scenario_id,
      option_id=sc$option_id,model_variant=sc$model_variant,horizon=sc$horizon,
      baseline=sc$baseline_case_id,rating_interpretation=config$rating_interpretation,
      validity_coverage=1,invalid_input_person_h=0,person_hours=ph,
      benefit_person_degC_h=B,energy_kWh=E,water_kg=sum(rr$water_kg_s*rr$dt_hours*3600),
      efficiency_person_degC_h_kWh=if(E>0) B/E else NA_real_,
      comfortable_person_h=sum(a$comfortable_person_h),
      incremental_comfortable_person_h=sum(a$incremental_comfortable_person_h),
      comfort_fraction=if(ph>0) sum(a$comfortable_person_h)/ph else NA_real_,
      residual_person_degC_h=sum(a$residual_person_degC_h),
      below_lower_person_h=sum(a$person_hours*(a$SET_C<config$comfort_lower_C)),
      safety_status='requires separately documented screen')
  })
  disparity<-aggregate(d[c('person_hours','residual_person_degC_h','comfortable_person_h')],d[c('case_id','zone_id','group_id')],sum)
  list(detail=d,comparison=do.call(rbind,totals),disparities=disparity)
}

scaling_check <- function(comfort) {
  a<-comfort$comparison
  # Algebraic duplication of an independent identical real zone/system, not observations.
  data.frame(case_id=a$case_id,energy_original=a$energy_kWh,energy_duplicated=2*a$energy_kWh,
    benefit_original=a$benefit_person_degC_h,benefit_duplicated=2*a$benefit_person_degC_h,
    efficiency_original=a$efficiency_person_degC_h_kWh,
    efficiency_duplicated=ifelse(a$energy_kWh>0,(2*a$benefit_person_degC_h)/(2*a$energy_kWh),NA_real_),
    interpretation='Algebraic independent-identical duplication only; shared flows invalidate this scaling')
}

run_checks_comfort <- function(config) {
  data.frame(check=c('installed SET signature and version','SET reference cases','paired aggregation','independent identical scaling','safety applicability'),
    status='BLOCKED',reason=c('comf installation/source audit required','Published reference values and tolerances required',
      'Complete matched cases required','Real inputs required for numerical check','Documented screen required; SET alone is insufficient'))
}
