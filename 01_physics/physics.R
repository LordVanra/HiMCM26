# HiMCM 2026 B. Definitions only: sourcing never starts an analysis.
# No project observations are embedded in these functions.

input_contract <- function() {
  # field:type:unit; c = character, n = real, i = integer.
  list(
    zones = c('venue_id:c:ID','zone_id:c:ID','volume_m3:n:m3','C_J_K:n:J/K','M_da_kg:n:kg dry air','cp_J_kgK:n:J/(kg K)','initial_T_C:n:degC','initial_w:n:kg/kg dry air'),
    flows = c('flow_id:c:ID','case_id:c:ID','timestamp:c:ISO8601','from:c:zone ID or OUTSIDE','to:c:zone ID or OUTSIDE','equipment_id:c:ID or NONE','mass_kg_s:n:kg/s','dry_mass_kg_s:n:kg dry air/s'),
    weather = c('case_id:c:ID','timestamp:c:ISO8601','dt_hours:n:h','temperature_C:n:degC','RH_percent:n:percent','pressure_Pa:n:Pa'),
    equipment = c('equipment_id:c:ID','case_id:c:ID','timestamp:c:ISO8601','device:c:A/B/C','count:i:devices','power_kW:n:kW per device','effectiveness:n:1','reference_T_C:n:degC','reference_RH_percent:n:percent','reference_pressure_Pa:n:Pa','reference_reduction_C:n:degC','bleed_drift_kg_s:n:kg/s per device','installation_status:c:actual or hypothetical'),
    surfaces = c('surface_id:c:ID','case_id:c:ID','timestamp:c:ISO8601','zone_id:c:ID','h_W_m2K:n:W/(m2 K)','area_m2:n:m2','surface_T_C:n:degC'),
    occupancy = c('case_id:c:ID','timestamp:c:ISO8601','zone_id:c:ID','group_id:c:ID','people:i:persons','sensible_W:n:W','moisture_kg_s:n:kg/s','local_airspeed_m_s:n:m/s','radiant_temperature_C:n:degC'),
    comfort_groups = c('group_id:c:ID','clo:n:clo','met:n:met','wme:n:met','sa:n:m2','ltime:n:min','ht:n:cm','wt:n:kg','tu:n:percent','csw:n:model coefficient','cdil:n:model coefficient','cstr:n:model coefficient','bodyPosition:c:sitting or standing'),
    scenarios = c('case_id:c:ID','venue_id:c:ID','venue_name:c:name','venue_role:c:bus/rail/real','climate:c:description','scenario_id:c:ID','option_id:c:NONE/A/B/C or policy ID','model_variant:c:agreed partition ID','baseline_case_id:c:ID','policy_description:c:precommitted rule and observable inputs','annual_weight:n:repetitions/year','horizon:c:description'),
    costs = c('venue_id:c:ID','option_id:c:ID','capital:n:currency','installation:n:currency','maintenance_year:n:currency/year','life_years:n:year','discount_rate:n:1/year','electricity_per_kWh:n:currency/kWh','water_per_kg:n:currency/kg','other_annual:n:currency/year','demand_annual:n:currency/year','currency:c:currency code'),
    constraints = c('venue_id:c:ID','budget_annual:n:currency/year','energy_kWh:n:kWh/horizon','water_kg:n:kg/horizon','min_comfort_fraction:n:1','safety_required:i:0 or 1','safety_method:c:documented method and applicability'),
    safety = c('case_id:c:ID','assessment_id:c:ID','passes:i:0 or 1','method:c:method','applicability:c:population and conditions'),
    uncertainty = c('sweep_id:c:ID','category:c:required sensitivity category','table:c:input table or config','row_id:i:row number','field:c:column','lower:n:field unit','upper:n:field unit','levels:i:count','pair_id:c:NONE or paired sweep ID','basis:c:evidence and applicability'),
    alternatives = c('alternative_id:c:ID','category:c:rating_interpretation or zone_partition','description:c:approved change','source:c:evidence'),
    registry = c('parameter_id:c:table.row.field or config.field','quantity:c:quantity','value:c:recorded value','unit:c:unit','source:c:provenance','status:c:provided/verified/derived','scope:c:venue/device/zone/time','lower:n:unit','upper:n:unit','notes:c:formula and source IDs for derived values')
  )
}

table_folder <- function(name) {
  if (name %in% c('comfort_groups')) return('02_comfort')
  if (name %in% c('costs','constraints','safety')) return('03_decision')
  if (name %in% c('uncertainty','alternatives')) return('04_sensitivity')
  '01_physics'
}

build_config <- function(root = '.') {
  list(root = root, run_id = NA_character_, mode = 'real_data',
    rating_interpretation = NA_character_, solver = NA_character_,
    timezone = NA_character_, rtol = NA_real_, atol = NA_real_,
    mass_tolerance = NA_real_, residual_tolerance = NA_real_,
    root_tolerance = NA_real_, tie_tolerance = NA_real_,
    comfort_upper_C = NA_real_, comfort_lower_C = NA_real_,
    psychrometric_approval = NA_character_, balance_approval = NA_character_,
    time_approval = NA_character_, steady_justification = NA_character_,
    set_audit = NA_character_, comf_version = NA_character_,
    desolve_version = NA_character_, ode_method = NA_character_,
    comparator = NA_character_, information_rule = NA_character_,
    horizon_approval = NA_character_, run_sensitivity = TRUE,
    monte_carlo_authorized = FALSE, mc_count = NA_integer_, mc_seed = NA_integer_,
    mc_model_source = NA_character_, mc_convergence = NA_character_,
    mc_draw = NULL, mc_converged = NULL, mc_probs = NA_real_,
    shelter_calibration = NULL, approved_alternatives = NULL,
    # These are function adapters for agreed models, never implicit defaults.
    sensitivity_recompute = NULL)
}

write_input_templates <- function(config) {
  for (nm in names(input_contract())) {
    fields <- strsplit(input_contract()[[nm]], ':', fixed = TRUE)
    x <- setNames(lapply(fields, function(f) switch(f[2],
      n = NA_real_, i = NA_integer_, c = NA_character_)), vapply(fields, `[`, '', 1))
    p <- file.path(config$root, table_folder(nm), paste0('input_', nm, '.csv'))
    if (!file.exists(p)) write.csv(as.data.frame(x), p, row.names = FALSE, na = '')
  }
  p <- file.path(config$root, '01_physics', 'input_problem_ratings.csv')
  if (!file.exists(p)) write.csv(data.frame(device=c('A','B','C'),
    maximum_reduction_C=c(3,5,8), power_kW=c(.25,1.2,2.5),
    reduction_kind=c('perceived','air temperature','air temperature'),
    reference_conditions=NA_character_, source='Supplied problem statement'), p,
    row.names=FALSE, na='')
  invisible(config)
}

load_inputs <- function(config) {
  lapply(setNames(names(input_contract()), names(input_contract())), function(nm) {
    f <- strsplit(input_contract()[[nm]], ':', fixed=TRUE)
    classes <- vapply(f, function(a) switch(a[2], n='numeric', i='integer', c='character'), '')
    p <- file.path(config$root, table_folder(nm), paste0('input_', nm, '.csv'))
    if (!file.exists(p)) return(NULL)
    raw <- read.csv(p, na.strings=c('', 'NA'), colClasses='character',
             check.names=FALSE, stringsAsFactors=FALSE, strip.white=TRUE)
    invalid <- character()
    for(j in seq_along(f)) if(f[[j]][1] %in% names(raw) && classes[j]!='character') {
      field<-f[[j]][1]; before<-raw[[field]]
      value<-suppressWarnings(as.numeric(before))
      bad<-which(!is.na(before) & (is.na(value) | !is.finite(value)))
      if(classes[j]=='integer') bad<-union(bad,which(!is.na(value) & value!=trunc(value)))
      invalid<-c(invalid,paste(nm,bad,field,sep='.')[seq_along(bad)])
      raw[[field]]<-if(classes[j]=='integer') suppressWarnings(as.integer(value)) else value
    }
    attr(raw,'invalid_fields')<-invalid
    raw
  })
}

readiness <- function(config, inputs, sensitivity=FALSE, monte_carlo=FALSE) {
  out <- list()
  add <- function(field, unit, scope, blocked, issue, where) {
    out[[length(out)+1L]] <<- data.frame(field=field, unit=unit, required_scope=scope,
      blocked_calculation=blocked, issue=issue, enter_in=where, stringsAsFactors=FALSE)
  }
  optional <- c('mc_count','mc_seed','mc_model_source','mc_convergence','mc_probs',
    'mc_draw','mc_converged','shelter_calibration','approved_alternatives',
    'sensitivity_recompute','steady_justification','desolve_version','ode_method')
  if (identical(config$solver,'steady')) optional <- setdiff(optional,'steady_justification')
  if (identical(config$solver,'dynamic')) optional <- setdiff(optional,c('desolve_version','ode_method'))
  if (sensitivity) optional <- setdiff(optional,c('approved_alternatives','sensitivity_recompute'))
  if (monte_carlo) optional <- setdiff(optional,c('mc_count','mc_seed','mc_model_source','mc_convergence','mc_probs','mc_draw','mc_converged'))
  if (identical(config$rating_interpretation,'shelter')) optional <- setdiff(optional,'shelter_calibration')
  for (nm in setdiff(names(config), optional)) {
    v <- config[[nm]]
    unit <- if (grepl('_C$',nm)) 'degC SET' else if (grepl('tolerance|rtol|atol',nm)) 'declared numerical units' else 'choice/ID'
    if (is.null(v) || (!is.function(v) && (anyNA(v) || any(trimws(as.character(v))==''))))
      add(paste0('config.',nm),unit,'project','all requested models','MISSING','build_config()')
  }
  if (!config$mode %in% 'real_data') add('config.mode','choice','project','all','INVALID','build_config()')
  for (nm in c('rtol','atol','root_tolerance','residual_tolerance','mass_tolerance','tie_tolerance'))
    if (!is.na(config[[nm]]) && (!is.finite(config[[nm]]) || config[[nm]] <= 0))
      add(paste0('config.',nm),'tolerance','project','all','must be finite and positive','build_config()')
  if (!is.na(config$solver) && !config$solver %in% c('steady','dynamic')) add('config.solver','choice','project','physics','steady or dynamic required','build_config()')
  if (!is.na(config$rating_interpretation) && !config$rating_interpretation %in% c('outlet','shelter')) add('config.rating_interpretation','choice','B/C','physics','outlet or shelter required','build_config()')
  if (!is.na(config$comparator) && !config$comparator %in% c('robust','scenario')) add('config.comparator','choice','project','regret','robust or scenario required','build_config()')
  for (nm in names(input_contract())) {
    if (!sensitivity && nm %in% c('uncertainty','alternatives')) next
    x <- inputs[[nm]]; schema <- strsplit(input_contract()[[nm]], ':', fixed=TRUE)
    for(field in attr(x,'invalid_fields')) add(field,'see schema',nm,'all dependent outputs','INVALID numeric/count text',paste0('input_',nm,'.csv'))
    for (f in schema) {
      if (nm=='registry' && f[1] %in% c('lower','upper')) next
      missing_column <- is.null(x) || !f[1] %in% names(x) || nrow(x)==0
      ix <- if (missing_column) NA_integer_ else which(is.na(x[[f[1]]]) | (is.character(x[[f[1]]]) & trimws(x[[f[1]]])==''))
      if (nm=='equipment' && !missing_column && f[1] %in% c('effectiveness','reference_T_C','reference_RH_percent','reference_pressure_Pa','reference_reduction_C')) ix <- ix[is.na(x$device[ix]) | x$device[ix]!='A']
      for (i in ix) add(paste(nm,ifelse(is.na(i),'required_row',i),f[1],sep='.'),f[3],
        paste('each applicable',nm,'record; keyed venue/device/zone/scenario/time'),
        paste(table_folder(nm),'and downstream outputs'),'MISSING',paste0(table_folder(nm),'/input_',nm,'.csv'))
      if (!missing_column && f[2] %in% c('n','i')) {
        bad <- which(!is.na(x[[f[1]]]) & !is.finite(x[[f[1]]]))
        for (i in bad) add(paste(nm,i,f[1],sep='.'),f[3],nm,'all dependent outputs','NONFINITE',paste0('input_',nm,'.csv'))
      }
    }
    if (!is.null(x) && nrow(x)>0 && nm!='registry') for (i in seq_len(nrow(x))) for (f in schema) {
      if (!f[1] %in% names(x) || is.na(x[[f[1]]][i])) next
      id <- paste(nm,i,f[1],sep='.')
      reg <- inputs$registry
      if (is.null(reg) || !any(!is.na(reg$parameter_id) & reg$parameter_id==id))
        add(id,f[3],nm,'provenance audit','MISSING provenance','01_physics/input_registry.csv')
    }
  }
  # Domain errors are collected even while other fields are still missing.
  ranges<-list(zones=list(volume_m3=c(0,Inf),C_J_K=c(0,Inf),M_da_kg=c(0,Inf),cp_J_kgK=c(0,Inf)),
    weather=list(RH_percent=c(0,100),pressure_Pa=c(0,Inf),dt_hours=c(0,Inf)),
    equipment=list(count=c(0,Inf),effectiveness=c(0,1),power_kW=c(0,Inf),reference_RH_percent=c(0,100)),
    occupancy=list(people=c(0,Inf),local_airspeed_m_s=c(0,Inf)),
    constraints=list(min_comfort_fraction=c(0,1),safety_required=c(0,1)),
    safety=list(passes=c(0,1)))
  for(nm in names(ranges)) for(f in names(ranges[[nm]])) {
    v<-inputs[[nm]][[f]]; limits<-ranges[[nm]][[f]]
    for(i in which(!is.na(v) & (v<limits[1] | v>limits[2])))
      add(paste(nm,i,f,sep='.'),'see input contract',nm,'all dependent outputs','OUT OF RANGE',paste0('input_',nm,'.csv'))
  }
  for (pkg in c('comf',if (identical(config$solver,'dynamic')) 'deSolve')) {
    if (!requireNamespace(pkg,quietly=TRUE)) add(paste0('package.',pkg),'version','runtime','SET or ODE','NOT INSTALLED','Install manually; then audit version')
  }
  if (monte_carlo && !isTRUE(config$monte_carlo_authorized)) add('mc_authorization','choice','project','Monte Carlo','NOT AUTHORIZED','build_config()')
  if (!length(out)) return(data.frame(field=character(),unit=character(),required_scope=character(),blocked_calculation=character(),issue=character(),enter_in=character()))
  do.call(rbind,out)
}

validate_inputs <- function(config, inputs=load_inputs(config), sensitivity=FALSE, monte_carlo=FALSE) {
  r <- readiness(config,inputs,sensitivity,monte_carlo)
  p <- file.path(config$root,'01_physics')
  write.csv(r,file.path(p,'result_data_readiness.csv'),row.names=FALSE,na='')
  writeLines(if(nrow(r)) c('ANALYSIS BLOCKED. No project calculations have run.',
    apply(r,1,function(z) paste(z,collapse=' | '))) else 'No missing fields found; semantic validation follows.',
    file.path(p,'missing_inputs.txt'))
  if(nrow(r)) stop('Analysis blocked: see 01_physics/result_data_readiness.csv and missing_inputs.txt',call.=FALSE)
  semantic_checks(config,inputs)
  invisible(TRUE)
}

semantic_checks <- function(config, x) {
  # These checks run before constructing any physical balance.
  positive <- list(zones=c('volume_m3','C_J_K','M_da_kg','cp_J_kgK'),weather=c('dt_hours','pressure_Pa'),costs='life_years')
  nonnegative <- list(flows=c('mass_kg_s','dry_mass_kg_s'),occupancy=c('people','local_airspeed_m_s'),
    surfaces=c('area_m2','h_W_m2K'),equipment=c('count','power_kW','bleed_drift_kg_s'),
    costs=c('capital','installation','maintenance_year','discount_rate','electricity_per_kWh','water_per_kg','other_annual','demand_annual'))
  errors <- character()
  for(nm in names(positive)) for(f in positive[[nm]]) if(any(x[[nm]][[f]]<=0)) errors <- c(errors,paste(nm,f,'must be positive'))
  for(nm in names(nonnegative)) for(f in nonnegative[[nm]]) if(any(x[[nm]][[f]]<0)) errors <- c(errors,paste(nm,f,'must be nonnegative'))
  if(any(x$weather$RH_percent<0 | x$weather$RH_percent>100)) errors<-c(errors,'weather RH must be 0..100 percent')
  if(any(!x$equipment$device %in% c('A','B','C'))) errors<-c(errors,'unsupported equipment device')
  if(anyDuplicated(x$scenarios$case_id)) errors<-c(errors,'duplicate case IDs')
  if(anyDuplicated(paste(x$zones$venue_id,x$zones$zone_id))) errors<-c(errors,'duplicate zone IDs within venue')
  if(any(!x$scenarios$baseline_case_id %in% x$scenarios$case_id)) errors<-c(errors,'baseline case missing')
  if(any(!x$scenarios$option_id %in% c('NONE','A','B','C'))) errors<-c(errors,'additional policies require explicit evaluator extension; only fixed NONE/A/B/C currently supported')
  if(any(!c('NONE','A','B','C') %in% x$scenarios$option_id)) errors<-c(errors,'candidate set must include NONE/A/B/C')
  if(length(unique(x$scenarios$venue_name[x$scenarios$venue_role=='real']))<2) errors<-c(errors,'two named real venues required')
  if(config$comfort_lower_C>config$comfort_upper_C) errors<-c(errors,'lower comfort bound exceeds upper')
  if(any(!x$occupancy$group_id %in% x$comfort_groups$group_id)) errors<-c(errors,'unresolved group key')
  if(anyDuplicated(x$comfort_groups$group_id)) errors<-c(errors,'duplicate group key')
  if(any(!x$constraints$safety_required %in% c(0L,1L)) || any(!x$safety$passes %in% c(0L,1L))) errors<-c(errors,'safety flags must be 0 or 1')
  for(nm in c('flows','weather','equipment','surfaces','occupancy','safety')) if(any(!x[[nm]]$case_id %in% x$scenarios$case_id)) errors<-c(errors,paste(nm,'unresolved case ID'))
  if(length(errors)) {
    r<-data.frame(field=errors,unit='see input contract',required_scope='project',blocked_calculation='all',issue='INVALID',enter_in='input CSV/config')
    write.csv(r,file.path(config$root,'01_physics','result_data_readiness.csv'),row.names=FALSE)
    writeLines(c('ANALYSIS BLOCKED',errors),file.path(config$root,'01_physics','missing_inputs.txt'))
    stop(paste(errors,collapse='; '),call.=FALSE)
  }
  invisible(TRUE)
}

# ASHRAE 2017 saturation and wet-bulb equations, as documented in PsychroLib.
# Empirical coefficients below define this named scientific model, not venue data.
# Domain is deliberately restricted to liquid-water wet bulbs >= 0 C.
sat_pressure <- function(T) {
  if(anyNA(T) || any(T<0 | T>200)) stop('Psychrometric domain: 0..200 C required')
  K<-T+273.15
  exp(-5.8002206e3/K+1.3914993-4.8640239e-2*K+4.1764768e-5*K^2-1.4452093e-8*K^3+6.5459673*log(K))
}
humidity_ratio <- function(T,RH,P) {
  if(anyNA(c(T,RH,P)) || RH<0 || RH>100 || P<=0) stop('Invalid psychrometric input')
  pv<-RH/100*sat_pressure(T)
  if(pv>=P) stop('Vapor pressure >= atmospheric pressure')
  0.621945*pv/(P-pv)
}
relative_humidity <- function(T,w,P) {
  if(anyNA(c(T,w,P)) || w<0 || P<=0) stop('Invalid humidity state')
  rh<-100*P*w/(0.621945+w)/sat_pressure(T)
  if(rh>100 || rh<0) stop('Supersaturated or invalid state; no clamping')
  rh
}
wet_bulb <- function(T,w,P,tol) {
  relative_humidity(T,w,P)
  f<-function(tw) {
    ws<-humidity_ratio(tw,100,P)
    ((2501-2.326*tw)*ws-1.006*(T-tw))/(2501+1.86*T-4.186*tw)-w
  }
  if(f(0)*f(T)>0) stop('Wet bulb below supported liquid-water domain')
  uniroot(f,c(0,T),tol=tol)$root
}
evaporative_supply <- function(T,w,P,e,config) {
  if(anyNA(e) || e<0 || e>1) stop('Invalid wet-bulb effectiveness')
  tw<-wet_bulb(T,w,P,config$root_tolerance)
  Ts<-T-e*(T-tw)
  # Constant moist-air enthalpy approximation; requires psychrometric_approval.
  h<-1.006*T+w*(2501+1.86*T)
  ws<-(h-1.006*Ts)/(2501+1.86*Ts)
  relative_humidity(Ts,ws,P)
  list(T=Ts,w=ws)
}

balance_system <- function(config,x,case,weather) {
  z<-x$zones[x$zones$venue_id==case$venue_id,,drop=FALSE]; n<-nrow(z)
  if(!n) stop('No zones for venue')
  select<-function(d) d[d$case_id==case$case_id & d$timestamp==weather$timestamp,,drop=FALSE]
  f<-select(x$flows); s<-select(x$surfaces); o<-select(x$occupancy); eq<-select(x$equipment)
  if(!nrow(f) || !nrow(o) || !nrow(s)) stop('Incomplete case/time coverage')
  if(case$option_id!='NONE' && !nrow(eq)) stop('Missing equipment')
  if(case$option_id=='NONE' && any(eq$count!=0)) stop('Baseline has active equipment')
  if(any(!c(f$from,f$to) %in% c(z$zone_id,'OUTSIDE'))) stop('Unresolved flow endpoint')
  if(any(!o$zone_id %in% z$zone_id) || any(!s$zone_id %in% z$zone_id)) stop('Unresolved zone')
  H<-matrix(0,n,n); W<-matrix(0,n,n); q<-g<-numeric(n)
  outside_w<-humidity_ratio(weather$temperature_C,weather$RH_percent,weather$pressure_Pa)
  water<-0 # exact empty sum, not a missing observation
  for(i in seq_len(n)) {
    zi<-z$zone_id[i]; incoming<-f[f$to==zi,,drop=FALSE]; outgoing<-f[f$from==zi,,drop=FALSE]
    if(abs(sum(incoming$mass_kg_s)-sum(outgoing$mass_kg_s))>config$mass_tolerance || abs(sum(incoming$dry_mass_kg_s)-sum(outgoing$dry_mass_kg_s))>config$mass_tolerance) stop('Unbalanced moist/dry air mass; difference form invalid')
    H[i,i]<- -sum(incoming$mass_kg_s)*z$cp_J_kgK[i]
    W[i,i]<- -sum(incoming$dry_mass_kg_s)
    for(j in seq_len(nrow(incoming))) {
      a<-incoming[j,]; k<-match(a$from,z$zone_id)
      if(a$equipment_id!='NONE') {
        device<-eq[eq$equipment_id==a$equipment_id,,drop=FALSE]
        if(nrow(device)!=1) stop('Equipment key must resolve exactly once')
        if(a$from!='OUTSIDE') stop('Evaporative recirculation requires an explicitly approved nonlinear extension')
        if(device$device=='A') stop('Fan must use local airspeed; do not mark as evaporative supply')
        refw<-humidity_ratio(device$reference_T_C,device$reference_RH_percent,device$reference_pressure_Pa)
        ref<-evaporative_supply(device$reference_T_C,refw,device$reference_pressure_Pa,device$effectiveness,config)
        if(config$rating_interpretation=='outlet' && abs(device$reference_T_C-ref$T-device$reference_reduction_C)>config$residual_tolerance) stop('Effectiveness inconsistent with reference rating')
        if(config$rating_interpretation=='shelter') {
          if(!is.function(config$shelter_calibration)) stop('Missing approved shelter calibration')
          config$shelter_calibration(device,x,case,config)
        }
        supply<-evaporative_supply(weather$temperature_C,outside_w,weather$pressure_Pa,device$effectiveness,config)
        water<-water+a$dry_mass_kg_s*(supply$w-outside_w)
        q[i]<-q[i]+a$mass_kg_s*z$cp_J_kgK[i]*supply$T; g[i]<-g[i]+a$dry_mass_kg_s*supply$w
      } else if(is.na(k)) {
        q[i]<-q[i]+a$mass_kg_s*z$cp_J_kgK[i]*weather$temperature_C
        g[i]<-g[i]+a$dry_mass_kg_s*outside_w
      } else {
        H[i,k]<-H[i,k]+a$mass_kg_s*z$cp_J_kgK[i]; W[i,k]<-W[i,k]+a$dry_mass_kg_s
      }
    }
    si<-s[s$zone_id==zi,,drop=FALSE]; oi<-o[o$zone_id==zi,,drop=FALSE]
    H[i,i]<-H[i,i]-sum(si$h_W_m2K*si$area_m2)
    q[i]<-q[i]+sum(si$h_W_m2K*si$area_m2*si$surface_T_C)+sum(oi$sensible_W)
    g[i]<-g[i]+sum(oi$moisture_kg_s)
  }
  list(z=z,H=H,W=W,q=q,g=g,occupancy=o,
    power=sum(eq$count*eq$power_kW),water=water+sum(eq$count*eq$bleed_drift_kg_s))
}

run_physics <- function(config,inputs=load_inputs(config)) {
  validate_inputs(config,inputs)
  rows<-groups<-resources<-list()
  for(ci in seq_len(nrow(inputs$scenarios))) {
    case<-inputs$scenarios[ci,]; weather<-inputs$weather[inputs$weather$case_id==case$case_id,,drop=FALSE]
    if(!nrow(weather)) stop('Missing weather case')
    times<-as.POSIXct(weather$timestamp,tz=config$timezone)
    if(anyNA(times) || anyDuplicated(times) || is.unsorted(times)) stop('Invalid/unsorted timestamps')
    if(length(times)>1 && any(abs(as.numeric(diff(times),units='hours')-head(weather$dt_hours,-1))>config$root_tolerance)) stop('Intervals must be contiguous with declared durations')
    state<-NULL
    for(t in seq_len(nrow(weather))) {
      a<-weather[t,]; b<-balance_system(config,inputs,case,a); n<-nrow(b$z)
      if(is.null(state)) state<-c(b$z$initial_T_C,b$z$initial_w)
      rhs<-function(time,y,parms) list(c((b$H%*%y[seq_len(n)]+b$q)/b$z$C_J_K,
        (b$W%*%y[n+seq_len(n)]+b$g)/b$z$M_da_kg))
      if(config$solver=='steady') {
        T<-as.vector(solve(b$H,-b$q)); w<-as.vector(solve(b$W,-b$g))
        if(max(abs(b$H%*%T+b$q))>config$residual_tolerance || max(abs(b$W%*%w+b$g))>config$residual_tolerance) stop('Balance residual exceeds tolerance')
      } else {
        if(as.character(utils::packageVersion('deSolve'))!=config$desolve_version) stop('deSolve version not audited')
        # Time bins are approved piecewise constant boundaries; exposure uses start state.
        T<-state[seq_len(n)]; w<-state[n+seq_len(n)]
        sol<-deSolve::ode(state,c(0,a$dt_hours*3600),rhs,parms=NULL,
          method=config$ode_method,rtol=config$rtol,atol=config$atol)
        state<-as.numeric(sol[nrow(sol),-1]); if(any(!is.finite(state))) stop('ODE failed')
      }
      for(i in seq_len(n)) {
        oi<-b$occupancy[b$occupancy$zone_id==b$z$zone_id[i],,drop=FALSE]
        if(!nrow(oi)) stop('Every zone needs occupancy including documented zero')
        if(length(unique(oi$local_airspeed_m_s))!=1 || length(unique(oi$radiant_temperature_C))!=1) stop('Split zones when local physical exposure differs by group')
        rows[[length(rows)+1L]]<-data.frame(run_id=config$run_id,venue_id=case$venue_id,case_id=case$case_id,
          scenario_id=case$scenario_id,option_id=case$option_id,zone_id=b$z$zone_id[i],timestamp=a$timestamp,
          dt_hours=a$dt_hours,temperature_C=T[i],humidity_ratio=w[i],RH_percent=relative_humidity(T[i],w[i],a$pressure_Pa),
          local_airspeed_m_s=oi$local_airspeed_m_s[1],radiant_temperature_C=oi$radiant_temperature_C[1],
          occupancy=sum(oi$people),power_kW=NA_real_,water_rate=NA_real_,valid=TRUE,
          diagnostic='Power kW and water kg/s are case-time totals in separate resource table',pressure_Pa=a$pressure_Pa)
      }
      groups[[length(groups)+1L]]<-b$occupancy
      resources[[length(resources)+1L]]<-data.frame(case_id=case$case_id,timestamp=a$timestamp,dt_hours=a$dt_hours,power_kW=b$power,water_kg_s=b$water)
    }
  }
  list(zone_conditions=do.call(rbind,rows),groups=do.call(rbind,groups),resources=do.call(rbind,resources))
}

run_checks_physics <- function(config) {
  r<-readiness(config,load_inputs(config),TRUE,FALSE)
  data.frame(check=c('input completeness','mass/energy/moisture residuals','published psychrometric cases','timestep convergence','independent validation'),
    status=c(if(nrow(r)) 'BLOCKED' else 'READY','BLOCKED','BLOCKED','BLOCKED','BLOCKED'),
    reason=c('See readiness report','Needs approved real inputs','Needs selected published reference cases and tolerances','Needs dynamic inputs and approved refinement','Needs separate matched observations'))
}
