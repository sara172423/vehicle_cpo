function [x, ev, h, ctx] = runAlgorithm(name, ctx, cfg)
    name = lower(char(name));
    switch name
        case {'cuckoo', 'dcsga'}
            [x, ev, h] = optim.cuckoo(ctx, cfg);

        case {'cpo', 'dcpo_base', 'dcpo_criticality', 'dcpo_cache'}
            cfg.variant = name;
            [x, ev, h] = optim.cpo(ctx, cfg);

        case 'gpc'
            [x, ev, h] = optim.gpc(ctx, cfg);

        case 'gwo'
            [x, ev, h] = optim.gwo(ctx, cfg);

        case 'puma'
            [x, ev, h] = optim.puma(ctx, cfg);

        otherwise
            error('Unknown algorithm %s', name);
    end
end
