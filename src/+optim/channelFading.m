function [shadow, ray] = channelFading(seeds, sigma)
    % Seeded channel shadowing and Rayleigh factors, compatible with Python.
    % Vectorized native CPython MT19937 integer initialization; first 3 uniforms.
    seeds = mod(double(seeds(:)), 2^32);
    n = numel(seeds);
    s = zeros(n, 624, 'uint32');
    s(:, 1) = 19650218;
    for i = 2:624
        x = bitxor(s(:, i - 1), bitshift(s(:, i - 1), -30));
        s(:, i) = uint32(mod(double(optim.PythonRandom.mul32(x, 1812433253)) + i - 1, 2^32));
    end
    i = 2;
    for k = 1:624
        x = bitxor(s(:, i - 1), bitshift(s(:, i - 1), -30));
        s(:, i) = uint32(mod(double(bitxor(s(:, i), optim.PythonRandom.mul32(x, 1664525))) + seeds, 2^32));
        i = i + 1;
        if i > 624
            s(:, 1) = s(:, 624);
            i = 2;
        end
    end
    for k = 1:623
        x = bitxor(s(:, i - 1), bitshift(s(:, i - 1), -30));
        s(:, i) = uint32(mod(double(bitxor(s(:, i), optim.PythonRandom.mul32(x, 1566083941))) - (i - 1), 2^32));
        i = i + 1;
        if i > 624
            s(:, 1) = s(:, 624);
            i = 2;
        end
    end
    s(:, 1) = uint32(2147483648);
    words = zeros(n, 6);
    % Only six first twisted words are needed; their sources are not yet modified.
    for i = 1:6
        y = bitor(bitand(s(:, i), uint32(2147483648)), bitand(s(:, i + 1), uint32(2147483647)));
        v = bitxor(s(:, i + 397), bitshift(y, -1));
        odd = logical(bitand(y, uint32(1)));
        v(odd) = bitxor(v(odd), uint32(2567483615));
        v = bitxor(v, bitshift(v, -11));
        v = bitxor(v, bitand(bitshift(v, 7), uint32(2636928640)));
        v = bitxor(v, bitand(bitshift(v, 15), uint32(4022730752)));
        v = bitxor(v, bitshift(v, -18));
        words(:, i) = double(v);
    end
    u = (floor(words(:, 1:2:5) / 32) * 67108864 + floor(words(:, 2:2:6) / 64)) / 9007199254740992;
    shadow = cos(u(:, 1) * 2 * pi) .* sqrt(-2 * log(1 - u(:, 2))) .* sigma(:);
    ray = max(-log(1 - u(:, 3)), 1e-12);
end
