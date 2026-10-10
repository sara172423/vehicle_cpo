function [x, ev, h, ctx] = runAlgorithm(name, ctx, cfg)
    name = lower(char(name));
    switch name
        case {'cuckoo', 'dcsga', 'to_v2i', 'to_wo_c', 'to_wo_r'}
            if strcmp(name, 'to_v2i')
                for t = ctx.optimTaskIds
                    dom = ctx.domain{t};
                    ctx.domain{t} = dom(ctx.isRsu(dom));
                end
            end
            if strcmp(name, 'to_wo_c')
                ctx.useCaching = false;
            end
            if strcmp(name, 'to_wo_r')
                ctx.optimTaskIds = ctx.unrankedTaskIds;
                ctx.scheduleOrder = [ctx.entryTaskIds ctx.optimTaskIds];
            end
            [x, ev, h] = optim.cuckoo(ctx, cfg);
        case {'cpo', 'dcpo_base', 'dcpo_criticality', 'dcpo_cache'}
            cfg.variant = name;
            [x, ev, h] = optim.cpo(ctx, cfg);
        case 'gpc'
            [x, ev, h] = optim.gpc(ctx, cfg);
        case {'gwo', 'gwo_aco'}
            [x, ev, h] = optim.gwo(ctx, cfg);
        case {'puma', 'po'}
            [x, ev, h] = optim.puma(ctx, cfg);
        case 'dtosc'
            [x, ev, h] = optim.dtosc(ctx, cfg);
        otherwise
            error('Unknown algorithm %s', name);
    end
end
