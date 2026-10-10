classdef Algorithm
    % Complete public algorithm-helper API of the uploaded library.
    % These abstract binary helpers are separate from the task-provider Cuckoo engine.
    methods (Static)

        function y = cs_position_update(x, omega, step)
            y = x(:)';
            n = min(numel(x), numel(step));
            for j = 1:n
                y(j) = x(j) + omega * step(j);
            end
        end

        function y = cs_exploitation_move(x, length)
            y = x(:)';
            for j = 1:min(max(0, fix(length)), numel(x))
                v = fix(y(j));
                if ismember(v, [0 1])
                    y(j) = 1 - v;
                else
                    y(j) = v;
                end
            end
        end

        function y = cs_random_walk_move(x, length)
            y = x(:)';
            for j = numel(x):-1:max(1, numel(x) - max(0, fix(length)) + 1)
                v = fix(y(j));
                if ismember(v, [0 1])
                    y(j) = 1 - v;
                else
                    y(j) = v;
                end
            end
        end

        function y = levy_step_mantegna(u, v, lambda)
            y = 0;
            if lambda > 0 && v ~= 0
                y = u / abs(v)^(1 / lambda);
            end
        end

        function y = levy_length_to_best(hamming, Nlevy)
            y = optim.PythonRandom.roundEven(2 * hamming * Nlevy);
        end

        function y = levy_length_random_walk(dimension, Nlevy)
            y = optim.PythonRandom.roundEven(2 * dimension * Nlevy);
        end

    end
end
