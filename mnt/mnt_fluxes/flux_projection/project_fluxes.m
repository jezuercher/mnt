function v_projected = project_fluxes(N, ind_ext, v_mean, v_std, v_sign, pars);

% v_projected = project_fluxes(N,ind_ext, v_mean, v_std, v_sign, pars);
%
% project fluxes to stationary subspace (different methods)
%
% pars.method:            'simple', 'one_norm',     'lasso',   'euclidean', 'thermo_correct', 
% pars.remove_eba_cycles: (flag) if set to 1, a matrix pars.C of eba-cycles has to be provided
% option 'thermo_correct' requires par.network

eval(default('pars','struct','v_std','[]','v_sign','[]'));

if size(v_mean,2)>1,
  for it = 1:size(v_mean,2),
    if length(v_std), vv1 = v_std(:,it); else vv1 = []; end
    if length(v_sign), vv2 = v_sign(:,it); else vv2 = []; end
    v_projected(:,it) = project_fluxes(N, ind_ext, v_mean(:,it), vv1, vv2, pars);
  end
  return
end

default_pars = struct('method','euclidean','ind_ignore',[],'remove_eba_cycles',0);
pars = join_struct(default_pars,pars);

if isempty(v_std),  v_std  = ones(size(v_mean)); end 
if isempty(v_sign), v_sign = nan * v_mean; end 

% make sure that reference fluxes respect zero flux and sign constraints

v_mean(v_sign == 0 )           = 0;
v_std( v_sign == 0 )           = 0.01 * nanstd(v_mean(:));
v_std( find(v_mean.*v_sign)<0) = nan;
v_mean(find(v_mean.*v_sign)<0) = nan;

external          = zeros(size(N,1),1); 
external(ind_ext) = 1;

display(sprintf('Projecting fluxes using "%s" method', pars.method));

switch pars.method,

  case 'simple',
    display('Simple projection - flux sign constraints are ignored');
    network.N                 = N;
    network.external          = zeros(size(N,1),1);
    network.external(ind_ext) = 1;
    v_projected               = es_make_fluxes_stationary(network,v_mean);

  case 'one_norm',    
    ind_finite        = find(isfinite(v_mean));
    [nm,nr] = size(N);
    A = N(external == 0,:);
    b = zeros(size(A,1),1);
    lb = v_mean(ind_finite)-v_std(ind_finite);
    ub = v_mean(ind_finite)+v_std(ind_finite);
    v_projected = my_lp_one_norm(A,b,lb,ub,100000);

  case 'lasso',    %% lasso regression
    ind_finite        = find(isfinite(v_mean));
    v_cov_inv         = diag(1./v_std(ind_finite).^2);
    if exist('external','var'), Nint = N(find(external ==0),:); end
    K = null(full(Nint));
    display('Running lasso regression, this can take a while');
    rho_mean = lasso(sqrt(v_cov_inv)* K(ind_finite,:),v_mean(ind_finite),0.1,10^-2,10^-1)
    v_projected = K * rho_mean;

  case 'euclidean', %% two-norm regression with constraints
    ind_finite        = find(isfinite(v_mean));
    v_mean            = v_mean(ind_finite);
    v_cov_inv         = diag(1./v_std(ind_finite).^2);
    [nm,nr] = size(N);
    if exist('external','var'), Nint = N(find(external ==0),:); end
    v_sign_finite= v_sign(ind_finite);
    ind_nonzeros = find(v_sign_finite~=0);
    v_sign_finite= v_sign_finite(ind_nonzeros);
    v_cov_inv    = v_cov_inv(ind_nonzeros,ind_nonzeros);
    my_v_mean    = v_mean(ind_nonzeros);
    ind_finite   = find(isfinite(my_v_mean));
    K            = null(full(Nint(:,find(v_sign ~=0 ))));
    rho_cov_inv  = K(ind_finite,:)' * v_cov_inv * K(ind_finite,:);
    %% safety measure to prevent unrealistic estimates of non-measured fluxes:
    if length(rho_cov_inv),
      rho_cov_inv  = rho_cov_inv + 10^-5 * max(eig(rho_cov_inv)) * eye(size(K,2));
    end
    rho_cov_inv  = 1/2 * [rho_cov_inv + rho_cov_inv'];
    epsilon      = 10^-10;
    y_mean       = K(ind_finite,:)' * v_cov_inv * my_v_mean(ind_finite);
    ind_signs = find(abs(v_sign_finite)==1);
    A         = -diag(v_sign_finite(ind_signs)) * K(ind_signs,:);
    b         = -epsilon * ones(length(ind_signs),1);
    rho_mean  = quadprog(rho_cov_inv,-y_mean,A,b);
    v_projected = zeros(nr,1);
    v_projected(ind_nonzeros,1) = K * rho_mean;
  
  case 'thermo_correct',
    dd.v.mean = v_mean;
    dd.v.std  = v_std;
    [options,es_constraints]  = es_default_options(pars.network);
    es_constraints.ext_sign   = nan * ones(length(ind_ext),1);
    es_constraints.v_sign     = v_sign; 
    es_constraints.ind_ignore = pars.ind_ignore; 
    v_projected               = feasible_fluxes(N,ind_ext,dd,es_constraints);
    
end

if pars.remove_eba_cycles,
  if ~isfield(pars,'C'), pars.C = nan; end
  [feasible,C,ind_non_orthogonal] = eba_feasible(v_projected,N,pars.C,[],'loose');
  if ~feasible,
    display('Removing unfeasible cycles');
    v_projected = eba_make_feasible(v_projected,N,'loose',pars.C);
  end
end

ind_finite = find(isfinite(v_mean));

if norm(v_projected(ind_finite)-v_mean(ind_finite)) / norm(v_mean(ind_finite)) > 0.5,
  [v_mean(ind_finite) v_projected(ind_finite)]
  figure(1000); plot(v_mean(ind_finite),v_projected(ind_finite),'.'); xlabel('flux'); ylabel('projected flux'); title('Flux change in project\_fluxes.m')
  warning('Projection leads to considerable change of fluxes'); 
end