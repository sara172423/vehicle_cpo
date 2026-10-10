function startup()
    % STARTUP Add project folders without relying on the user's MATLAB path.
    root = fileparts(mfilename('fullpath'));
    addpath(root);
    addpath(fullfile(root, 'config'));
    addpath(fullfile(root, 'src'));
    fprintf('VEFC MATLAB project ready: %s\n', root);
end
