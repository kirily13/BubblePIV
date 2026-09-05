%% SHADOWGRAPH BUBBLE IMAGE TRACKING SCRIPT VER. 2
clear; clc; close all
%% SECTION 1: find, read and store the post-processed bubble images
imageFolder = uigetdir('',"Select Folder with Tiff files"); %select the folder with the images

if imageFolder == 0 %No folder it fails
    error('No Image Folder Selected')
else
    tiffFiles = fullfile(imageFolder,'*.tif*');%only reads tif files
    fileList = dir(tiffFiles); %retrieves image information from the files
    numFiles = numel(fileList); %counts how many images were stored
    fileSize = fileList(1).name; %grabs file size
    imgSize = imread(fullfile(imageFolder, fileSize)); %reads only one file to find the dimensions (1024 x 1024)
    imgStack = zeros(size(imgSize,1),size(imgSize,2),numFiles,'uint8');
    for i = 1:numFiles 
        fileName = fileList(i).name; %grabs each file name
        img = imread(fullfile(imageFolder, fileName)); %reads them and grabs their information
        imgStack(:,:,i) = img;
    end
end

analysisFolder = fullfile(imageFolder,'Output Folder'); %making an output folder for later
if ~isfolder(analysisFolder)
    mkdir(analysisFolder)
end
%% SECTION 2: CALIBRATION
%This section involves calibration using a ruler
disp("Select Ruler Photo")
[fileCalibration,directoryCalibration] = uigetfile('*.tif');
if isequal(fileCalibration,0)
    error('No Ruler Selected');
else
    imgCalibration = imread(fullfile(directoryCalibration,fileCalibration));
    calFig = figure; 
    imagesc(imgCalibration)
    axis image; colormap gray; xlabel('X Pixel'); ylabel('Y Pixel');
    [x1,y1] = ginput(1);
    [x2,y2] = ginput(1);
    deltX = x2 - x1; deltY = y2 - y1;
    pixelDist = hypot(deltX,deltY);
    trueLengthInch = input("Length Between Two Points in Inches: ");
    metersPerPixel = (trueLengthInch * 0.0254) / pixelDist; 
    fprintf('Millimeters per pixel: %.9g mm/pixel\n', metersPerPixel*1000);
    close(calFig)
end
%% SECTION 3: BUBBLE RISE SEQUENCE, ROI, AND MASK 
%Select the frame when the bubble first appears
bubbleDetach = input('Enter frame when bubble detaches from needle: ');
if isempty(bubbleDetach)
    error("No Frame Number Selected")
else
bubbleFrameSequence = bubbleDetach:numFiles;
bubbleRiseStack = imgStack(:,:,bubbleFrameSequence);
bubbleImgROI = imgStack(:,:,bubbleFrameSequence(1));
roiFig = figure; 
imagesc(bubbleImgROI)
axis image; colormap gray; xlabel('X Pixel'); ylabel('Y Pixel');
ROI = drawrectangle("Color",'r');
wait(ROI);
roiRawDimensions = round(ROI.Position);
exportgraphics(roiFig,fullfile(analysisFolder,'ROI Calibration Figure.png'),'Resolution',200)
disp('ROI Calibration background image saved in output folder')
close(roiFig)
end 
x1ROI = roiRawDimensions(1); 
y1ROI = roiRawDimensions(2);
x2ROI = roiRawDimensions(3) + x1ROI - 1;
y2ROI = roiRawDimensions(4) + y1ROI - 1;
%Develop a logical mask
broadMask = false(1024,1024);
broadMask(y1ROI:y2ROI, x1ROI:x2ROI) = true;


%% SECTION 4: Segmentation / Median Background Subtraction 
backgroundCount = 100;
sampleIndicesBackground = unique(round(linspace(1,numFiles,backgroundCount)));
imgStackBackground = imgStack(:,:,sampleIndicesBackground);
backgroundImage = median(imgStackBackground,3);
backgroundFullPath = fullfile(analysisFolder, 'Background Image.tif');
imwrite(backgroundImage, backgroundFullPath)
disp('Median background image saved in output folder')

%Segmentation 
backgroundDifference = max((backgroundImage - bubbleRiseStack), 0);
roiBackDiff = backgroundDifference(broadMask);
otsuSegmentation = 255 .* graythresh(roiBackDiff);
bubbleMask = double(backgroundDifference) >= otsuSegmentation; 
bubbleMask = bubbleMask & broadMask;
bubbleMask = imopen(bubbleMask,strel('disk',1,0));
bubbleMask = imclose(bubbleMask,strel('disk',2,0));
%Segmentation Image For Reference
otsuSegmentationFig = figure;
bubbleMaskImage = bubbleMask(:,:,bubbleFrameSequence(1));
imagesc(bubbleMaskImage);
axis image; colormap gray; xlabel('X Pixel'); ylabel('Y Pixel');
exportgraphics(otsuSegmentationFig,fullfile(analysisFolder,'Segmentation Calibration Figure.png'),'Resolution',200)
close(otsuSegmentationFig)
%% Section 5: Bubble Tracking
bubbleFrameIndex = numel(bubbleFrameSequence);
detectedFrames = false(bubbleFrameIndex,1);
xCentroid = nan(bubbleFrameIndex,1);
yCentroid = nan(bubbleFrameIndex,1);
bubbleVolumePixels = nan(bubbleFrameIndex,1);
bubbleDiameterPixels = nan(bubbleFrameIndex,1);
areaPxMax = 5000; areaPxMin = 500; maxStep = 20;
prevArea = [];
prevCentroid = [];

for bfi = 1:bubbleFrameIndex
    rawPixData = regionprops(bubbleMask(:,:,bfi),'Area','Centroid','PixelIdxList'); 
    allCentroids = reshape([rawPixData.Centroid],2,[])';
    allAreas = [rawPixData.Area]';
    if bfi == 1
        validSizeArea = allAreas >= areaPxMin & allAreas <= areaPxMax;
        if any(validSizeArea)
            detectedFrames(bfi) = true;
        else
            fprintf('Bubble Missed At: %d\n', bfi)
            error('First Bubble Not Detected. Try again')
        end

        validIndices = find(validSizeArea);
        [prevArea,prevAreaIndex] = max(allAreas(validSizeArea));
        prevCentroid = allCentroids(validIndices(prevAreaIndex),:);
        selectedArea = prevArea;
        selectedCentroid = prevCentroid;
    else
       if any(bubbleMask(y1ROI, x1ROI:x2ROI,bfi)) || any(bubbleMask(y2ROI, x1ROI:x2ROI,bfi)) || any(bubbleMask(y1ROI:y2ROI, x1ROI,bfi)) || any(bubbleMask(y1ROI:y2ROI, x2ROI,bfi))
            detectedFrames(bfi) = false;
            fprintf('Bubble hit ROI At: %d\n', bfi)
            continue
       end
       validSizeArea = allAreas >= areaPxMin & allAreas <= areaPxMax;
       if any(validSizeArea)
            detectedFrames(bfi) = true;
       else
            fprintf('Bubble Missed At: %d\n', bfi)
            continue
       end
       newArea = (allAreas(validSizeArea));
       newCentroid = allCentroids(validSizeArea,:);
       areaWeight = .5*(abs((newArea - prevArea)) / areaPxMax);
       normalizedDistance = (hypot(newCentroid(:,1) - prevCentroid(:,1), newCentroid(:,2) - prevCentroid(:,2)))/maxStep;
       [trackScore,trackScoreIndex] = min(areaWeight + normalizedDistance);
       selectedArea = newArea(trackScoreIndex);
       selectedCentroid = newCentroid(trackScoreIndex,:); 
       prevArea = selectedArea;
       prevCentroid = selectedCentroid;
    end
%Section 5.5: Raw Calculations via Bubble Tracking
    if detectedFrames(bfi) == true
        %Centroid Calculations
        [~,xPixelLoctMask] = find(bubbleMask(:,:,bfi)); %Extracts all the x pixel locations in the mask. 
        [yPixelLoctMask,~] = find(bubbleMask(:,:,bfi)); %Extracts all the y pixel locations in the mask. 
        %Every pixel in the mask is a 255 / 1 in bit depth. Therefore, we
        %can assume it has a constant density. Enabling the simplification of the centroid equation. 
        %Once the centroid has simplified, it needs to be reduced to remann
        %summations, which can be further simplified based on how pixels work
        totDA = numel(xPixelLoctMask); %bottom integral of the formula. Since every dA is 1 px^2, we really just the need the summation of how many of those areas are there to calculate the total area of the bubble. 
        xdA = sum(xPixelLoctMask*1); %intg(x * dA). Top integral. dA for a pixel is just 1.
        ydA = sum(yPixelLoctMask*1); %same thing but for y.
        xCentroid(bfi) = xdA / totDA; %The formal integral. sum(x * Da) / A. 
        yCentroid(bfi) = ydA / totDA;
        %diameter calculation via disk method
        bubbleVolumeFrame = 0; %Since the volume is being added in each row, it must start at 0
        yPixLoop = unique(yPixelLoctMask)'; %every unique y row that applies to the bubble mask in the specific frame
        for bfiDiameter = yPixLoop
            yDiaIndex = find(yPixelLoctMask == bfiDiameter); %returns the indices of all the bubble pixels located on that current y-row. This enables for all the x pixels that match to be found. 
            xPixTemp = xPixelLoctMask(yDiaIndex); %finds all the x pixels that apply
            radius = (max(xPixTemp) - min(xPixTemp) + 1) / 2; %determines the radius
            bubbleVolumeFrame = bubbleVolumeFrame + (pi * radius^2 * 1); %calculates the volume one disk at a time (delt y is 1 because each pixel is 1x1)
        end
        bubbleVolumePixels(bfi) = bubbleVolumeFrame; %once every disk has been stacked, the total volume is stored for each frame
        bubbleDiameterPixels(bfi) = ((6*bubbleVolumePixels(bfi)) / pi)^(1/3); %the diameter is then calculated based on the equation for the volume-equivalent sphere diameter.
    end
end
bubbleDiameterMM = bubbleDiameterPixels .* (metersPerPixel * 1000);
xCentroidMM = xCentroid .* (metersPerPixel * 1000);
yCentroidMM = yCentroid .* (metersPerPixel * 1000);

%% SECTION 6: Calculations
time = 1/500; %seconds per frame
%Velocity Centroid Calculation
xVelocityCentroid = nan((numel(xCentroidMM)),1);
yVelocityCentroid = nan((numel(xCentroidMM)),1);
for CenVIndex = 2:numel(xCentroidMM)
    xVelocityCentroid(CenVIndex) = (((xCentroidMM(CenVIndex)) - (xCentroidMM(CenVIndex-1)))/1000) / time;
    yVelocityCentroid(CenVIndex) = (((yCentroidMM(CenVIndex)) - (yCentroidMM(CenVIndex-1)))/1000) / time;
end
VelocityTotal = hypot(xVelocityCentroid,yVelocityCentroid);

%Acceleration Centroid Calculation
xAccelerationCentroid = nan((numel(xVelocityCentroid)),1);
yAccelerationCentroid = nan((numel(yVelocityCentroid)),1);
for CenAIndex = 2:numel(xVelocityCentroid)
    xAccelerationCentroid(CenAIndex) = ((xVelocityCentroid(CenAIndex)) - (xVelocityCentroid(CenAIndex-1))) / time;
    yAccelerationCentroid(CenAIndex) = ((yVelocityCentroid(CenAIndex)) - (yVelocityCentroid(CenAIndex-1))) / time;
end

%% SECTION 7: PLOTS
%Centroid trajectories
figure;
plot(xCentroidMM, yCentroidMM, 'r-');
xlabel('X Centroid (mm)','FontSize',20);
ylabel('Y Centroid (mm)','FontSize',20);
title('Centroid Trajectories of Bubbles','FontSize',25);
grid on;

%Y-Centroid versus Time
time_range = (0:(numel(xCentroidMM))-1)*time;
figure;
plot(time_range, yCentroidMM, 'r-');
xlabel('time [s]','FontSize',20);
ylabel('Y Centroid (mm)','FontSize',20);
title('Y Centroid Versus Time','FontSize',25);
grid on;

%Diameter versus Y Centroid
figure;
plot(bubbleDiameterMM, yCentroidMM, 'r-');
xlabel('Bubble Diameter (mm)','FontSize',20);
ylabel('Y Centroid (mm)','FontSize',20);
title('Y Centroid Versus Bubble Diameter','FontSize',25);
grid on;

%Velocity X versus Y Centroid
figure;
plot(xVelocityCentroid, yCentroidMM, 'r-');
xlabel('V_x Centroid (m/s)','FontSize',20);
ylabel('X Centroid (mm)','FontSize',20);
title('Y Centroid Versus Bubble Diameter','FontSize',25);
grid on;

%Velocity Y versus Y Centroid
figure;
plot(yVelocityCentroid, yCentroidMM, 'r-');
xlabel('V_y Centroid (m/s)','FontSize',20);
ylabel('Y Centroid (mm)','FontSize',20);
title('Y Centroid Versus V_y Centroid','FontSize',25);
grid on;

%Accel X versus Y Centroid
figure;
plot(xAccelerationCentroid, yCentroidMM, 'r-');
xlabel('A_x Centroid (m/s^2)','FontSize',20);
ylabel('Y Centroid (mm)','FontSize',20);
title('Y Centroid Versus A_x Centroid','FontSize',25);
grid on;

%Accel Y versus Y Centroid
figure;
plot(yAccelerationCentroid, yCentroidMM, 'r-');
xlabel('A_y Centroid (m/s^2)','FontSize',20);
ylabel('Y Centroid (mm)','FontSize',20);
title('Y Centroid Versus A_y Centroid','FontSize',25);
grid on;

%% SECTION 8: Non Dimensional Numbers and Averages
liquidDensity = 998.2;      %density of the liquid/water [kg/m^3]
gasDensity = 1.204;         %density of the air [kg/m^3]
dynamicViscosity = 1.002e-3; %dynamic viscoity of the liquid/water [Pa*s]
surfaceTension = 0.0728;      %surface tension between the liquid and gas [N/m]
gravity = 9.795;             %gravitational acceleration [m/s^2]

xVelocityAvg = mean(xVelocityCentroid,'omitnan');
xVelocityStd = std(xVelocityCentroid,'omitnan');
xVelocityCombined = compose("%.2f ± %.2f",xVelocityAvg,xVelocityStd);

yVelocityAvg = mean(yVelocityCentroid,'omitnan');
yVelocityStd = std(yVelocityCentroid,'omitnan');
yVelocityCombined = compose("%.2f ± %.2f",yVelocityAvg,yVelocityStd);

xAccelerationAvg = mean(xAccelerationCentroid,'omitnan');
xAccelerationStd = std(xAccelerationCentroid,'omitnan');
xAccelerationCombined = compose("%.2f ± %.2f",xAccelerationAvg,xAccelerationStd);

yAccelerationAvg = mean(yAccelerationCentroid,'omitnan');
yAccelerationStd = std(yAccelerationCentroid,'omitnan');
yAccelerationCombined = compose("%.2f ± %.2f",yAccelerationAvg,yAccelerationStd);

Reynolds_number = mean(liquidDensity .* VelocityTotal .* (bubbleDiameterMM/1000) ./ dynamicViscosity,'omitnan');
Reynolds_numberStd = std(liquidDensity .* VelocityTotal .* (bubbleDiameterMM/1000) ./ dynamicViscosity , 'omitnan');
ReynoldsCombined = compose("%.2f ± %.2f",Reynolds_number,Reynolds_numberStd);



Etovos_number = mean((((liquidDensity-gasDensity)) .* gravity .* ((bubbleDiameterMM/1000)).^2) ./ surfaceTension , 'omitnan');
Etovos_numberStd = std((((liquidDensity-gasDensity)) .* gravity .* ((bubbleDiameterMM/1000)).^2) ./ surfaceTension , 'omitnan');
EtovosCombined = compose("%.2f ± %.2f",Etovos_number,Etovos_numberStd);

Weber_number = mean(liquidDensity .* ((VelocityTotal)).^2 .* (bubbleDiameterMM/1000) ./ surfaceTension , 'omitnan');
Weber_numberStd = std(liquidDensity .* ((VelocityTotal)).^2 .* (bubbleDiameterMM/1000) ./ surfaceTension , 'omitnan');
WeberCombined = compose("%.2f ± %.2f",Weber_number,Weber_numberStd);

resultsTable = table(ReynoldsCombined, EtovosCombined, WeberCombined, xVelocityCombined, yVelocityCombined, xAccelerationCombined, yAccelerationCombined,...
    'VariableNames', {'Reynolds Number', 'Eotvos Number','Weber Number', 'Avg X Velocity','Avg Y Velocity','Avg X Acceleration','Avg Y Acceleration'});
disp(resultsTable)